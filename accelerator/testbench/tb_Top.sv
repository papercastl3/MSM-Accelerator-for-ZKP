`timescale 1ns / 1ps

`define ZYNQ_VIP_INST tb_Top.dut.TopDesign1_i.zynq_ultra_ps_e_0.inst

module tb_Top;

    // ============================================================
    // User parameters
    // ============================================================

    localparam int POINT_NUM      = 16;
    localparam int SCALAR_NUM     = 16;

    localparam int POINT_BITS     = 512;
    localparam int SCALAR_BITS    = 256;

    localparam int POINT_BYTES    = POINT_BITS  / 8;
    localparam int SCALAR_BYTES   = SCALAR_BITS / 8;

    localparam int POINT_TOTAL_BYTES  = POINT_NUM  * POINT_BYTES;
    localparam int SCALAR_TOTAL_BYTES = SCALAR_NUM * SCALAR_BYTES;

    localparam int RESULT_BITS        = 768;
    localparam int RESULT_BYTES       = RESULT_BITS / 8;

    // ?ô∞Í∑£Îòª??ç†?èô?òô???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô??ç†?èô?òô ? 4096 beat ???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô ??ç†?èô?òô ????ç†?èô?òô??ç†?èô?òô??ç†?èô?òô???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô??ç†?èô?òô ? ???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô
    // ???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô Top???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô TLAST??ç†?èô?òô ? ???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô ??ç†?èô?òô??ç†?èô?òô??ç†?èô?òô ???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô??ç†?èô?òô ? S2MM?? ??ç†?èô?òô ? ??ç†?èô?òô ????ç†?èô?òô??ç†?èô?òô??ç†?èô?òô???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô ???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô??ç†?èô?òô??ç†?èô?òô?ç† ?
    localparam int RESULT_MAX_BEATS   = 8 * 2048;
    localparam int RESULT_MAX_BYTES   = RESULT_MAX_BEATS * RESULT_BYTES;

    // Same input vectors are streamed and processed multiple times.
    // Each pass writes its result to a different DDR region.
    localparam int PASS_NUM           = 3;
    localparam int RESULT_ALL_BYTES   = PASS_NUM * RESULT_MAX_BYTES;

    // ============================================================
    // Address map
    // ============================================================
    //
    // Address Editor:
    //   axi_dma_0 S_AXI_LITE : 0xA000_0000, 64K
    //   axi_dma_1 S_AXI_LITE : 0xA001_0000, 64K
    //
    //   axi_dma_0 Data_MM2S / Data_S2MM / Data_SG -> HP0 DDR LOW
    //   axi_dma_1 Data_MM2S / Data_SG            -> HP0 DDR LOW
    //
    // ============================================================

    localparam longint unsigned DDR_POINT_BASE        = 64'h0000_0000_1000_0000;
    localparam longint unsigned DDR_SCALAR_BASE       = 64'h0000_0000_1001_0000;

    localparam longint unsigned DDR_DMA0_MM2S_BD_BASE = 64'h0000_0000_1002_0000;
    localparam longint unsigned DDR_DMA1_MM2S_BD_BASE = 64'h0000_0000_1003_0000;
    localparam longint unsigned DDR_DMA0_S2MM_BD_BASE = 64'h0000_0000_1004_0000;

    localparam longint unsigned DDR_RESULT_BASE       = 64'h0000_0000_1010_0000;

    localparam longint unsigned DMA0_BASE             = 64'h0000_0000_A000_0000;
    localparam longint unsigned DMA1_BASE             = 64'h0000_0000_A001_0000;

    // ============================================================
    // AXI DMA register offsets
    // ============================================================

    localparam int MM2S_DMACR         = 32'h00;
    localparam int MM2S_DMASR         = 32'h04;
    localparam int MM2S_CURDESC       = 32'h08;
    localparam int MM2S_CURDESC_MSB   = 32'h0C;
    localparam int MM2S_TAILDESC      = 32'h10;
    localparam int MM2S_TAILDESC_MSB  = 32'h14;

    localparam int S2MM_DMACR         = 32'h30;
    localparam int S2MM_DMASR         = 32'h34;
    localparam int S2MM_CURDESC       = 32'h38;
    localparam int S2MM_CURDESC_MSB   = 32'h3C;
    localparam int S2MM_TAILDESC      = 32'h40;
    localparam int S2MM_TAILDESC_MSB  = 32'h44;

    // ============================================================
    // AXI DMA control/status bits
    // ============================================================

    localparam bit [31:0] DMACR_RS        = 32'h0000_0001;
    localparam bit [31:0] DMACR_RESET     = 32'h0000_0004;
    localparam bit [31:0] DMACR_IOC_IRQEN = 32'h0000_1000;
    localparam bit [31:0] DMACR_ERR_IRQEN = 32'h0000_4000;

    localparam bit [31:0] DMASR_HALTED    = 32'h0000_0001;
    localparam bit [31:0] DMASR_IDLE      = 32'h0000_0002;
    localparam bit [31:0] DMASR_IOC_IRQ   = 32'h0000_1000;
    localparam bit [31:0] DMASR_DLY_IRQ   = 32'h0000_2000;
    localparam bit [31:0] DMASR_ERR_IRQ   = 32'h0000_4000;
    localparam bit [31:0] DMASR_IRQ_ALL   = 32'h0000_7000;

    // ============================================================
    // AXI DMA SG BD offsets
    // ============================================================

    localparam int BD_NEXTDESC        = 32'h00;
    localparam int BD_NEXTDESC_MSB    = 32'h04;
    localparam int BD_BUFFER_ADDR     = 32'h08;
    localparam int BD_BUFFER_ADDR_MSB = 32'h0C;
    localparam int BD_CONTROL         = 32'h18;
    localparam int BD_STATUS          = 32'h1C;

    localparam bit [31:0] BD_CTRL_TXSOF       = 32'h0800_0000;
    localparam bit [31:0] BD_CTRL_TXEOF       = 32'h0400_0000;
    localparam bit [31:0] BD_CTRL_BTT_MASK    = 32'h007F_FFFF;

    localparam bit [31:0] BD_STS_COMPLETE     = 32'h8000_0000;
    localparam bit [31:0] BD_STS_DEC_ERR      = 32'h4000_0000;
    localparam bit [31:0] BD_STS_SLV_ERR      = 32'h2000_0000;
    localparam bit [31:0] BD_STS_INT_ERR      = 32'h1000_0000;
    localparam bit [31:0] BD_STS_RXSOF        = 32'h0800_0000;
    localparam bit [31:0] BD_STS_RXEOF        = 32'h0400_0000;
    localparam bit [31:0] BD_STS_ACTUAL_LEN_MASK = 32'h007F_FFFF;

    // ============================================================
    // HEX storage
    // ============================================================

    reg [POINT_BITS-1:0]  point_mem  [0:POINT_NUM-1];
    reg [SCALAR_BITS-1:0] scalar_mem [0:SCALAR_NUM-1];

    string point_hex_file  = "point.hex";
    string scalar_hex_file = "scalar.hex";

    // ============================================================
    // DUT
    // ============================================================

    TopDesign1_wrapper dut();

    // ============================================================
    // VIP response
    // ============================================================

    bit [1:0] resp;

    // ============================================================
    // PS VIP access tasks
    // ============================================================

    task automatic ps_write32(
        input longint unsigned addr,
        input bit [31:0] data
    );
        bit [127:0] wr_data;
    begin
        if (addr[1:0] != 2'b00) begin
            $display("[%0t] PS WRITE ERROR: unaligned addr=%h", $time, addr);
            $fatal;
        end

        wr_data = '0;
        wr_data[31:0] = data;

        `ZYNQ_VIP_INST.write_data(addr, 4, wr_data, resp);

        if (resp != 2'b00) begin
            $display("[%0t] PS WRITE ERROR addr=%h data=%h resp=%0d",
                    $time, addr, data, resp);
            $fatal;
        end
    end
    endtask

    task automatic ps_read32(
        input  longint unsigned addr,
        output bit [31:0] data
    );
        bit [127:0] rd_data;
        longint unsigned aligned_addr;
        int lane;
    begin
        if (addr[1:0] != 2'b00) begin
            $display("[%0t] PS READ ERROR: unaligned addr=%h", $time, addr);
            $fatal;
        end

        aligned_addr = addr & 64'hFFFF_FFFF_FFFF_FFF0;
        lane = addr[3:2];

        rd_data = '0;

        //  ?ç† ? ?ç† ? 16-byte aligned ?õÖ?öØ?àò??ç†?èô?òô ?ç† ? ?ç† ? 16 byte  ??ç†?èô?òô?ç† ? 
        `ZYNQ_VIP_INST.read_data(aligned_addr, 16, rd_data, resp);

        if (resp != 2'b00) begin
            $display("[%0t] PS READ ERROR addr=%h aligned_addr=%h resp=%0d",
                    $time, addr, aligned_addr, resp);
            $fatal;
        end

        case (lane)
            0: data = rd_data[31:0];
            1: data = rd_data[63:32];
            2: data = rd_data[95:64];
            3: data = rd_data[127:96];
            default: data = 32'hxxxx_xxxx;
        endcase
    end
    endtask

    task automatic ps_write64_split(
        input longint unsigned addr,
        input longint unsigned data
    );
    begin
        ps_write32(addr + 0, data[31:0]);
        ps_write32(addr + 4, data[63:32]);
    end
    endtask

    // ============================================================
    // DDR/OCM backdoor memory access tasks
    // ============================================================
    //
    // IMPORTANT:
    // - write_data/read_data: AXI master transaction to PL address map.
    //   Use for DMA control registers: 0xA000_0000, 0xA001_0000.
    //
    // - write_mem/read_mem: Backdoor DDR/OCM memory access inside PS VIP.
    //   Use for DDR payload, SG BD, and result buffer.
    //
    // Zynq UltraScale+ PS VIP API order:
    //   write_mem(data[1023:0], start_addr[31:0], no_of_bytes)
    //   read_mem(start_addr[31:0], no_of_bytes, data[1023:0])
    //
    // ============================================================

    task automatic ps_mem_write32(
        input longint unsigned addr,
        input bit [31:0] data
    );
        bit [1023:0] mem_data;
    begin
        if (addr[1:0] != 2'b00) begin
            $display("[%0t] PS MEM WRITE ERROR: unaligned addr=%h", $time, addr);
            $fatal;
        end

        mem_data = '0;
        mem_data[31:0] = data;

        `ZYNQ_VIP_INST.write_mem(mem_data, addr[31:0], 4);
    end
    endtask

    task automatic ps_mem_read32(
        input  longint unsigned addr,
        output bit [31:0] data
    );
        bit [1023:0] mem_data;
    begin
        if (addr[1:0] != 2'b00) begin
            $display("[%0t] PS MEM READ ERROR: unaligned addr=%h", $time, addr);
            $fatal;
        end

        mem_data = '0;

        `ZYNQ_VIP_INST.read_mem(addr[31:0], 4, mem_data);

        data = mem_data[31:0];
    end
    endtask

    task automatic check_file_readable(
        input string file_name
    );
        int fd;
    begin
        fd = $fopen(file_name, "r");

        if (fd == 0) begin
            $display("[%0t] ERROR: cannot open file: %s", $time, file_name);
            $display("        Put the file in the xsim working directory or pass +POINT_HEX=<path> / +SCALAR_HEX=<path>.");
            $fatal;
        end

        $fclose(fd);
    end
    endtask

    // ============================================================
    // DDR load tasks
    // ============================================================

    task automatic load_point_to_ddr;
        int i;
        int w;
        bit [31:0] word32;
        longint unsigned addr;
    begin
        check_file_readable(point_hex_file);
        $readmemh(point_hex_file, point_mem);

        for (i = 0; i < POINT_NUM; i++) begin
            for (w = 0; w < POINT_BYTES / 4; w++) begin
                word32 = point_mem[i][w*32 +: 32];
                addr   = DDR_POINT_BASE + i*POINT_BYTES + w*4;
                ps_mem_write32(addr, word32);
            end
        end

        $display("[%0t] POINT DDR load done: base=%h bytes=%0d",
                 $time, DDR_POINT_BASE, POINT_TOTAL_BYTES);
    end
    endtask

    task automatic load_scalar_to_ddr;
        int i;
        int w;
        bit [31:0] word32;
        longint unsigned addr;
    begin
        check_file_readable(scalar_hex_file);
        $readmemh(scalar_hex_file, scalar_mem);

        for (i = 0; i < SCALAR_NUM; i++) begin
            for (w = 0; w < SCALAR_BYTES / 4; w++) begin
                word32 = scalar_mem[i][w*32 +: 32];
                addr   = DDR_SCALAR_BASE + i*SCALAR_BYTES + w*4;
                ps_mem_write32(addr, word32);
            end
        end

        $display("[%0t] SCALAR DDR load done: base=%h bytes=%0d",
                 $time, DDR_SCALAR_BASE, SCALAR_TOTAL_BYTES);
    end
    endtask

    task automatic clear_result_ddr;
        int i;
    begin
        for (i = 0; i < RESULT_ALL_BYTES / 4; i++) begin
            ps_mem_write32(DDR_RESULT_BASE + i*4, 32'h0000_0000);
        end

        $display("[%0t] RESULT DDR clear done: base=%h bytes=%0d",
                 $time, DDR_RESULT_BASE, RESULT_ALL_BYTES);
    end
    endtask

    // ============================================================
    // BD helper
    // ============================================================

    task automatic clear_bd_64bytes(
        input longint unsigned bd_addr
    );
        int i;
    begin
        for (i = 0; i < 16; i++) begin
            ps_mem_write32(bd_addr + i*4, 32'h0000_0000);
        end
    end
    endtask

    // ============================================================
    // MM2S BD creation
    // ============================================================

    task automatic make_mm2s_bd(
        input longint unsigned bd_addr,
        input longint unsigned buffer_addr,
        input int unsigned     transfer_bytes
    );
        bit [31:0] control;
    begin
        clear_bd_64bytes(bd_addr);

        control = BD_CTRL_TXSOF |
                  BD_CTRL_TXEOF |
                  (transfer_bytes[22:0] & BD_CTRL_BTT_MASK);

        ps_mem_write32(bd_addr + BD_NEXTDESC,        bd_addr[31:0]);
        ps_mem_write32(bd_addr + BD_NEXTDESC_MSB,    bd_addr[63:32]);

        ps_mem_write32(bd_addr + BD_BUFFER_ADDR,     buffer_addr[31:0]);
        ps_mem_write32(bd_addr + BD_BUFFER_ADDR_MSB, buffer_addr[63:32]);

        ps_mem_write32(bd_addr + BD_CONTROL, control);
        ps_mem_write32(bd_addr + BD_STATUS,  32'h0000_0000);

        $display("[%0t] MM2S BD created: bd=%h buf=%h bytes=%0d control=%h",
                 $time, bd_addr, buffer_addr, transfer_bytes, control);
    end
    endtask

    // ============================================================
    // S2MM BD creation
    // ============================================================

    task automatic make_s2mm_bd(
        input longint unsigned bd_addr,
        input longint unsigned buffer_addr,
        input int unsigned     buffer_bytes
    );
        bit [31:0] control;
    begin
        clear_bd_64bytes(bd_addr);

        control = buffer_bytes[22:0] & BD_CTRL_BTT_MASK;

        ps_mem_write32(bd_addr + BD_NEXTDESC,        bd_addr[31:0]);
        ps_mem_write32(bd_addr + BD_NEXTDESC_MSB,    bd_addr[63:32]);

        ps_mem_write32(bd_addr + BD_BUFFER_ADDR,     buffer_addr[31:0]);
        ps_mem_write32(bd_addr + BD_BUFFER_ADDR_MSB, buffer_addr[63:32]);

        ps_mem_write32(bd_addr + BD_CONTROL, control);
        ps_mem_write32(bd_addr + BD_STATUS,  32'h0000_0000);

        $display("[%0t] S2MM BD created: bd=%h buf=%h max_bytes=%0d control=%h",
                 $time, bd_addr, buffer_addr, buffer_bytes, control);
    end
    endtask

    // ============================================================
    // DMA reset tasks
    // ============================================================

    task automatic dma_mm2s_reset(
        input longint unsigned dma_base
    );
        bit [31:0] status;
        int timeout;
    begin
        ps_write32(dma_base + MM2S_DMACR, DMACR_RESET);

        timeout = 1000;
        do begin
            ps_read32(dma_base + MM2S_DMACR, status);
            timeout--;
        end while ((status & DMACR_RESET) != 0 && timeout > 0);

        if (timeout == 0) begin
            $display("[%0t] DMA MM2S reset timeout: base=%h",
                     $time, dma_base);
            $fatal;
        end

        ps_write32(dma_base + MM2S_DMASR, DMASR_IRQ_ALL);

        $display("[%0t] DMA MM2S reset done: base=%h",
                 $time, dma_base);
    end
    endtask

    task automatic dma_s2mm_reset(
        input longint unsigned dma_base
    );
        bit [31:0] status;
        int timeout;
    begin
        ps_write32(dma_base + S2MM_DMACR, DMACR_RESET);

        timeout = 1000;
        do begin
            ps_read32(dma_base + S2MM_DMACR, status);
            timeout--;
        end while ((status & DMACR_RESET) != 0 && timeout > 0);

        if (timeout == 0) begin
            $display("[%0t] DMA S2MM reset timeout: base=%h",
                     $time, dma_base);
            $fatal;
        end

        ps_write32(dma_base + S2MM_DMASR, DMASR_IRQ_ALL);

        $display("[%0t] DMA S2MM reset done: base=%h",
                 $time, dma_base);
    end
    endtask

    // ============================================================
    // DMA start tasks
    // ============================================================

    task automatic dma_mm2s_start_sg(
        input longint unsigned dma_base,
        input longint unsigned bd_addr
    );
        bit [31:0] status;
    begin
        ps_write32(dma_base + MM2S_CURDESC,     bd_addr[31:0]);
        ps_write32(dma_base + MM2S_CURDESC_MSB, bd_addr[63:32]);

        ps_write32(dma_base + MM2S_DMACR,
                   DMACR_RS | DMACR_IOC_IRQEN | DMACR_ERR_IRQEN);

        ps_write32(dma_base + MM2S_TAILDESC,     bd_addr[31:0]);
        ps_write32(dma_base + MM2S_TAILDESC_MSB, bd_addr[63:32]);

        ps_read32(dma_base + MM2S_DMASR, status);

        $display("[%0t] DMA MM2S SG started: base=%h bd=%h status=%h",
                 $time, dma_base, bd_addr, status);
    end
    endtask

    task automatic dma_s2mm_start_sg(
        input longint unsigned dma_base,
        input longint unsigned bd_addr
    );
        bit [31:0] status;
    begin
        ps_write32(dma_base + S2MM_CURDESC,     bd_addr[31:0]);
        ps_write32(dma_base + S2MM_CURDESC_MSB, bd_addr[63:32]);

        ps_write32(dma_base + S2MM_DMACR,
                   DMACR_RS | DMACR_IOC_IRQEN | DMACR_ERR_IRQEN);

        ps_write32(dma_base + S2MM_TAILDESC,     bd_addr[31:0]);
        ps_write32(dma_base + S2MM_TAILDESC_MSB, bd_addr[63:32]);

        ps_read32(dma_base + S2MM_DMASR, status);

        $display("[%0t] DMA S2MM SG started: base=%h bd=%h status=%h",
                 $time, dma_base, bd_addr, status);
    end
    endtask

    // ============================================================
    // DMA wait tasks
    // ============================================================

    task automatic dma_mm2s_wait_done(
        input longint unsigned dma_base
    );
        bit [31:0] status;
        int timeout;
    begin
        timeout = 1000000;

        do begin
            ps_read32(dma_base + MM2S_DMASR, status);
            timeout--;
        end while (((status & DMASR_IOC_IRQ) == 0) &&
                   ((status & DMASR_ERR_IRQ) == 0) &&
                   timeout > 0);

        if (timeout == 0) begin
            $display("[%0t] DMA MM2S wait timeout: base=%h status=%h",
                     $time, dma_base, status);
            $fatal;
        end

        if ((status & DMASR_ERR_IRQ) != 0) begin
            $display("[%0t] DMA MM2S error: base=%h status=%h",
                     $time, dma_base, status);
            $fatal;
        end

        $display("[%0t] DMA MM2S done: base=%h status=%h",
                 $time, dma_base, status);

        ps_write32(dma_base + MM2S_DMASR, DMASR_IOC_IRQ);
    end
    endtask

    task automatic dma_s2mm_wait_done(
        input longint unsigned dma_base
    );
        bit [31:0] status;
        int timeout;
    begin
        timeout = 100000;

        do begin
            ps_read32(dma_base + S2MM_DMASR, status);
            timeout--;

            
                // $display("[%0t] S2MM waiting... timeout_left=%0d status=%h",
                //         $time, timeout, status);
                // peek_s2mm("DMA S2MM wait");
            
        end while (((status & DMASR_IOC_IRQ) == 0) &&
                   ((status & DMASR_ERR_IRQ) == 0) &&
                   timeout > 0);

        if (timeout == 0) begin
            $display("[%0t] DMA S2MM wait timeout: base=%h status=%h",
                     $time, dma_base, status);
            $fatal;
        end

        if ((status & DMASR_ERR_IRQ) != 0) begin
            $display("[%0t] DMA S2MM error: base=%h status=%h",
                     $time, dma_base, status);
            $fatal;
        end

        $display("[%0t] DMA S2MM done: base=%h status=%h",
                 $time, dma_base, status);

        ps_write32(dma_base + S2MM_DMASR, DMASR_IOC_IRQ);
    end
    endtask

    // ============================================================
    // BD status check
    // ============================================================

    task automatic check_mm2s_bd_status(
        input longint unsigned bd_addr
    );
        bit [31:0] status;
    begin
        ps_mem_read32(bd_addr + BD_STATUS, status);

        $display("[%0t] MM2S BD status: bd=%h status=%h",
                 $time, bd_addr, status);

        if ((status & BD_STS_COMPLETE) == 0) begin
            $display("[%0t] MM2S BD not complete", $time);
            $fatal;
        end

        if ((status & (BD_STS_DEC_ERR | BD_STS_SLV_ERR | BD_STS_INT_ERR)) != 0) begin
            $display("[%0t] MM2S BD error: status=%h", $time, status);
            $fatal;
        end
    end
    endtask

    task automatic check_s2mm_bd_status(
        input  longint unsigned bd_addr,
        output int unsigned     actual_bytes
    );
        bit [31:0] status;
    begin
        ps_mem_read32(bd_addr + BD_STATUS, status);

        actual_bytes = status & BD_STS_ACTUAL_LEN_MASK;

        $display("[%0t] S2MM BD status: bd=%h status=%h actual_bytes=%0d",
                 $time, bd_addr, status, actual_bytes);

        if ((status & BD_STS_COMPLETE) == 0) begin
            $display("[%0t] S2MM BD not complete", $time);
            $fatal;
        end

        if ((status & (BD_STS_DEC_ERR | BD_STS_SLV_ERR | BD_STS_INT_ERR)) != 0) begin
            $display("[%0t] S2MM BD error: status=%h", $time, status);
            $fatal;
        end

        if ((status & BD_STS_RXEOF) == 0) begin
            $display("[%0t] WARNING: S2MM BD RXEOF is not set. TLAST may not be received.", $time);
        end
    end
    endtask

    // ============================================================
    // Result dump
    // ============================================================

    task automatic dump_result_from_ddr(
        input longint unsigned base_addr,
        input int unsigned     actual_bytes
    );
        localparam int RESULT_WORDS = RESULT_BYTES / 4; // 768 / 32 = 24

        int beat;
        int w;
        int actual_beats;
        bit [31:0] word32;
        bit [RESULT_BITS-1:0] result_data;
    begin
        if ((actual_bytes % RESULT_BYTES) != 0) begin
            $display("[%0t] ERROR: actual_bytes=%0d is not aligned to RESULT_BYTES=%0d",
                    $time, actual_bytes, RESULT_BYTES);
            $fatal;
        end

        actual_beats = actual_bytes / RESULT_BYTES;

        $display("[%0t] RESULT DDR human-readable dump start: base=%h actual_bytes=%0d beats=%0d",
                $time, base_addr, actual_bytes, actual_beats);

        for (beat = 0; beat < actual_beats; beat++) begin
            result_data = '0;

            // DDR ???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô?? ?õÖ?öØ?àò??ç†?èô?òô??ç†?èô?òô ????ç†?èô?òô??ç†?èô?òô??ç†?èô?òô ???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô result_data???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô ???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô?? ??ç†?èô?òôË¢Å„ÇãÎ±???ç†?èô?òô ????ç†?èô?òô??ç†?èô?òô??ç†?èô?òô ?ç† ?Ë¢Å—äÏÇï?
            for (w = 0; w < RESULT_WORDS; w++) begin
                ps_mem_read32(base_addr + beat*RESULT_BYTES + w*4, word32);
                result_data[w*32 +: 32] = word32;
            end

            // ???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô ?ô∞Í∑®Ïòô???ç†?èô?òô ?çÑ?éªÎ´???ç†?èô?òô: result[767:0] ???ç†?èô?òô??ç†?èô?òô??ç†?èô?òôÁ≠åÔΩã?ôã??ç†?èô?òô?? ???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô???ç†?èô?òô??ç†?èô?òô??ç†?èô?òô??ç†?èô?òôË¢Å„ÇãÎ±???ç†?èô?òô ????ç†?èô?òô??ç†?èô?òô??ç†?èô?òô ??ç†?èô?òô??ç†?èô?òô??ç†?èô?òô
            $display("result[%0d] = %h", beat, result_data);
        end

        $display("[%0t] RESULT DDR human-readable dump done", $time);
    end
    endtask

    task automatic dump_result_from_ddr_to_file(
        input longint unsigned base_addr,
        input int unsigned     actual_bytes,
        input string           out_file
    );
        localparam int RESULT_WORDS = RESULT_BYTES / 4; // 768 / 32 = 24

        int beat;
        int w;
        int actual_beats;
        int fd;

        bit [31:0] word32;
        bit [RESULT_BITS-1:0] result_data;
    begin
        if ((actual_bytes % RESULT_BYTES) != 0) begin
            $display("[%0t] ERROR: actual_bytes=%0d is not aligned to RESULT_BYTES=%0d",
                    $time, actual_bytes, RESULT_BYTES);
            $fatal;
        end

        actual_beats = actual_bytes / RESULT_BYTES;

        fd = $fopen(out_file, "w");
        if (fd == 0) begin
            $display("[%0t] ERROR: cannot open result output file: %s",
                    $time, out_file);
            $fatal;
        end

        $display("[%0t] RESULT DDR dump to file start: base=%h actual_bytes=%0d beats=%0d file=%s",
                $time, base_addr, actual_bytes, actual_beats, out_file);

        for (beat = 0; beat < actual_beats; beat++) begin
            result_data = '0;

            // DDR ??ç†?èô?òô  ?ç† ?   ?õÖ?öØ?àò??ç†?èô?òô word??ç†?èô?òô  result_data ??ç†?èô?òô  ?ç† ?   ??ç†?èô?òôË¢Å„ÇãÎ±???ç†?èô?òô  ?ç† ? ?ç† ??ç† ? 
            for (w = 0; w < RESULT_WORDS; w++) begin
                ps_mem_read32(base_addr + beat*RESULT_BYTES + w*4, word32);
                result_data[w*32 +: 32] = word32;
            end

            //  ?ç† ? È§ìŒ∫Ïë¥?ç† ? 768-bit hex  ?ç† ? ?ç† ? ?ç† ?    ??ç†?èô?òô
            $fdisplay(fd, "%h", result_data);
        end

        $fclose(fd);

        $display("[%0t] RESULT DDR dump to file done: %s",
                $time, out_file);
    end
    endtask

    // ============================================================
    // Optional debug dump
    // ============================================================

    task automatic dump_dma_status(
        input string name,
        input longint unsigned dma_base
    );
        bit [31:0] mm2s_cr;
        bit [31:0] mm2s_sr;
        bit [31:0] s2mm_cr;
        bit [31:0] s2mm_sr;
    begin
        ps_read32(dma_base + MM2S_DMACR, mm2s_cr);
        ps_read32(dma_base + MM2S_DMASR, mm2s_sr);
        ps_read32(dma_base + S2MM_DMACR, s2mm_cr);
        ps_read32(dma_base + S2MM_DMASR, s2mm_sr);

        $display("[%0t] %s DMA:",
                $time, name);
        $display("  MM2S_DMACR=%h MM2S_DMASR=%h", mm2s_cr, mm2s_sr);
        $display("  S2MM_DMACR=%h S2MM_DMASR=%h", s2mm_cr, s2mm_sr);
    end
    endtask

    // ============================================================
    // Main sequence
    // ============================================================

    initial begin
        int unsigned s2mm_actual_bytes;
        int pass;
        int result_fd_init;
        longint unsigned result_base;
        string result_file;

        if (!$value$plusargs("POINT_HEX=%s", point_hex_file)) begin
            point_hex_file = "point.hex";
        end

        if (!$value$plusargs("SCALAR_HEX=%s", scalar_hex_file)) begin
            scalar_hex_file = "scalar.hex";
        end

        if (!$value$plusargs("RESULT_HEX=%s", result_file)) begin
            result_file = "result_all.hex";
        end

        // Truncate once at simulation start.
        // Each pass appends to the same file.
        result_fd_init = $fopen(result_file, "w");
        if (result_fd_init == 0) begin
            $display("[%0t] ERROR: cannot open result output file: %s",
                     $time, result_file);
            $fatal;
        end
        $fclose(result_fd_init);

        $display("[%0t] TB start", $time);
        $display("[%0t] POINT_HEX  = %s", $time, point_hex_file);
        $display("[%0t] SCALAR_HEX = %s", $time, scalar_hex_file);
        $display("[%0t] RESULT_HEX = %s", $time, result_file);

        // --------------------------------------------------------
        // PS VIP reset sequence
        // --------------------------------------------------------
        `ZYNQ_VIP_INST.set_debug_level_info(0);
        `ZYNQ_VIP_INST.set_stop_on_error(1);

        `ZYNQ_VIP_INST.por_srstb_reset(1'b0);
        `ZYNQ_VIP_INST.fpga_soft_reset(32'hFFFF_FFFF);

        #2000;

        `ZYNQ_VIP_INST.por_srstb_reset(1'b1);
        `ZYNQ_VIP_INST.fpga_soft_reset(32'h0000_0000);

        #2000;
//        $stop;

        // --------------------------------------------------------
        // 1. DDR initialization
        // --------------------------------------------------------
        load_point_to_ddr();
        load_scalar_to_ddr();
        clear_result_ddr();
//        $stop;

        // --------------------------------------------------------
        // 2. Run 3 DMA passes
        // --------------------------------------------------------
        for (pass = 0; pass < PASS_NUM; pass++) begin
            result_base = DDR_RESULT_BASE + pass * RESULT_MAX_BYTES;

            $display("[%0t] ===== PASS %0d START =====", $time, pass);
            $display("[%0t] PASS %0d result_base=%h result_file=%s",
                     $time, pass, result_base, result_file);

            // ----------------------------------------------------
            // 2-1. Re-create SG BDs for this pass
            //      MM2S input buffers are reused.
            //      S2MM output buffer changes every pass.
            // ----------------------------------------------------
            make_mm2s_bd(
                DDR_DMA0_MM2S_BD_BASE,
                DDR_POINT_BASE,
                POINT_TOTAL_BYTES
            );

            make_mm2s_bd(
                DDR_DMA1_MM2S_BD_BASE,
                DDR_SCALAR_BASE,
                SCALAR_TOTAL_BYTES
            );

            make_s2mm_bd(
                DDR_DMA0_S2MM_BD_BASE,
                result_base,
                RESULT_MAX_BYTES
            );

            // ----------------------------------------------------
            // 2-2. Reset DMA channels only
            //      Do not reset the PL compute core here.
            //      The PL internal pass counter must keep progressing.
            // ----------------------------------------------------
            dma_mm2s_reset(DMA0_BASE);
            dma_mm2s_reset(DMA1_BASE);
            dma_s2mm_reset(DMA0_BASE);
            #2000;

            dump_dma_status("DMA0", DMA0_BASE);
            dump_dma_status("DMA1", DMA1_BASE);

            // ----------------------------------------------------
            // 2-3. Start S2MM first
            // ----------------------------------------------------
            dma_s2mm_start_sg(DMA0_BASE, DDR_DMA0_S2MM_BD_BASE);
            #1000;

            // ----------------------------------------------------
            // 2-4. Start MM2S point/scalar
            // ----------------------------------------------------
            dma_mm2s_start_sg(DMA0_BASE, DDR_DMA0_MM2S_BD_BASE);
            dma_mm2s_start_sg(DMA1_BASE, DDR_DMA1_MM2S_BD_BASE);

            // ----------------------------------------------------
            // 2-5. Wait MM2S done
            // ----------------------------------------------------
            dma_mm2s_wait_done(DMA0_BASE);
            dma_mm2s_wait_done(DMA1_BASE);

            check_mm2s_bd_status(DDR_DMA0_MM2S_BD_BASE);
            check_mm2s_bd_status(DDR_DMA1_MM2S_BD_BASE);

            // ----------------------------------------------------
            // 2-6. Wait S2MM done
            // ----------------------------------------------------
            dma_s2mm_wait_done(DMA0_BASE);

            check_s2mm_bd_status(
                DDR_DMA0_S2MM_BD_BASE,
                s2mm_actual_bytes
            );

            if (s2mm_actual_bytes == 0) begin
                $display("[%0t] ERROR: PASS %0d S2MM actual_bytes is zero",
                         $time, pass);
                $fatal;
            end

            if (s2mm_actual_bytes != RESULT_MAX_BYTES) begin
                $display("[%0t] WARNING: PASS %0d actual_bytes=%0d expected=%0d",
                         $time, pass, s2mm_actual_bytes, RESULT_MAX_BYTES);
            end

            // ----------------------------------------------------
            // 2-7. Dump this pass result to a file
            // ----------------------------------------------------
             dump_result_from_ddr_to_file_fast(
                 result_base,
                 s2mm_actual_bytes,
                 result_file
             );

            $display("[%0t] ===== PASS %0d DONE =====", $time, pass);
//            $stop;
        end

        // --------------------------------------------------------
        // 9. Finish
        // --------------------------------------------------------
        dump_dma_status("DMA0", DMA0_BASE);
        dump_dma_status("DMA1", DMA1_BASE);

        #1000;

        $display("[%0t] TB PASS", $time);
        $finish;
    end

    task automatic debug_dma_raw128(
        input string name,
        input longint unsigned dma_base
    );
        bit [127:0] raw0;
        bit [127:0] raw3;
    begin
        raw0 = '0;
        raw3 = '0;

        // 0x00 ~ 0x0C: MM2S_DMACR, MM2S_DMASR, CURDESC, CURDESC_MSB
        `ZYNQ_VIP_INST.read_data(dma_base + 32'h00, 16, raw0, resp);

        // 0x30 ~ 0x3C: S2MM_DMACR, S2MM_DMASR, CURDESC, CURDESC_MSB
        `ZYNQ_VIP_INST.read_data(dma_base + 32'h30, 16, raw3, resp);

        $display("[%0t] %s RAW MM2S block @%h = %032h", $time, name, dma_base + 32'h00, raw0);
        $display("  [31:0]    MM2S_DMACR       = %h", raw0[31:0]);
        $display("  [63:32]   MM2S_DMASR       = %h", raw0[63:32]);
        $display("  [95:64]   MM2S_CURDESC     = %h", raw0[95:64]);
        $display("  [127:96]  MM2S_CURDESC_MSB = %h", raw0[127:96]);

        $display("[%0t] %s RAW S2MM block @%h = %032h", $time, name, dma_base + 32'h30, raw3);
        $display("  [31:0]    S2MM_DMACR       = %h", raw3[31:0]);
        $display("  [63:32]   S2MM_DMASR       = %h", raw3[63:32]);
        $display("  [95:64]   S2MM_CURDESC     = %h", raw3[95:64]);
        $display("  [127:96]  S2MM_CURDESC_MSB = %h", raw3[127:96]);
    end
    endtask

    task automatic peek_s2mm(
        input string tag
    );
        bit [31:0] status;
        bit [31:0] bd_status;
        bit [31:0] bd_control;
        int unsigned actual_bytes;
    begin
        ps_read32(DMA0_BASE + S2MM_DMASR, status);
        ps_mem_read32(DDR_DMA0_S2MM_BD_BASE + BD_STATUS, bd_status);

        actual_bytes = bd_status & BD_STS_ACTUAL_LEN_MASK;

        $display("[%0t] ===== S2MM PEEK: %s =====", $time, tag);
        $display("  S2MM_DMASR   = %h", status);
        $display("  BD_STATUS    = %h", bd_status);
        $display("  actual_bytes = %0d", actual_bytes);
        $display("  actual_beats = %0d", actual_bytes / RESULT_BYTES);

        $display("  DMA halted   = %0d", (status & DMASR_HALTED) != 0);
        $display("  DMA idle     = %0d", (status & DMASR_IDLE) != 0);
        $display("  DMA IOC_IRQ  = %0d", (status & DMASR_IOC_IRQ) != 0);
        $display("  DMA ERR_IRQ  = %0d", (status & DMASR_ERR_IRQ) != 0);

        $display("  BD complete  = %0d", (bd_status & BD_STS_COMPLETE) != 0);
        $display("  BD RXSOF     = %0d", (bd_status & BD_STS_RXSOF) != 0);
        $display("  BD RXEOF     = %0d", (bd_status & BD_STS_RXEOF) != 0);
        $display("  BD DEC_ERR   = %0d", (bd_status & BD_STS_DEC_ERR) != 0);
        $display("  BD SLV_ERR   = %0d", (bd_status & BD_STS_SLV_ERR) != 0);
        $display("  BD INT_ERR   = %0d", (bd_status & BD_STS_INT_ERR) != 0);

        

        ps_mem_read32(DDR_DMA0_S2MM_BD_BASE + BD_CONTROL, bd_control);

        $display("  BD_CONTROL   = %h", bd_control);
        $display("  BD_BTT       = %0d", bd_control & BD_CTRL_BTT_MASK);
    end
    endtask

    task automatic ps_mem_read_result768(
        input  longint unsigned addr,
        output bit [RESULT_BITS-1:0] data
    );
        bit [1023:0] mem_data;
    begin
        if (addr[1:0] != 2'b00) begin
            $display("[%0t] PS MEM READ ERROR: unaligned addr=%h", $time, addr);
            $fatal;
        end

        mem_data = '0;

        // RESULT_BYTES = 96 bytes
        `ZYNQ_VIP_INST.read_mem(addr[31:0], RESULT_BYTES, mem_data);

        data = mem_data[RESULT_BITS-1:0];
    end
    endtask

    task automatic dump_result_from_ddr_to_file_fast(
        input longint unsigned base_addr,
        input int unsigned     actual_bytes,
        input string           out_file
    );
        int beat;
        int actual_beats;
        int fd;

        bit [RESULT_BITS-1:0] result_data;
    begin
        if ((actual_bytes % RESULT_BYTES) != 0) begin
            $display("[%0t] ERROR: actual_bytes=%0d is not aligned to RESULT_BYTES=%0d",
                    $time, actual_bytes, RESULT_BYTES);
            $fatal;
        end

        actual_beats = actual_bytes / RESULT_BYTES;

        fd = $fopen(out_file, "a");
        if (fd == 0) begin
            $display("[%0t] ERROR: cannot open result output file: %s",
                    $time, out_file);
            $fatal;
        end

        $display("[%0t] RESULT DDR fast dump start: base=%h actual_bytes=%0d beats=%0d file=%s",
                $time, base_addr, actual_bytes, actual_beats, out_file);

        for (beat = 0; beat < actual_beats; beat++) begin
            ps_mem_read_result768(
                base_addr + beat * RESULT_BYTES,
                result_data
            );

            $fdisplay(fd, "%h", result_data);
        end

        $fclose(fd);

        $display("[%0t] RESULT DDR fast dump done: %s", $time, out_file);
    end
    endtask

endmodule