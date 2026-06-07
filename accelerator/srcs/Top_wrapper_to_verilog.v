`timescale 1ns / 1ps

module Top_wrapper_to_verilog (
    input  wire          aclk,
    input  wire          aresetn,

    // AXI4-Stream Slave input: point DMA
    input  wire  [511:0] s0_axis_tdata,
    input  wire          s0_axis_tvalid,
    output wire          s0_axis_tready,
    input  wire          s0_axis_tlast,

    // AXI4-Stream Slave input: scalar DMA
    input  wire  [255:0] s1_axis_tdata,
    input  wire          s1_axis_tvalid,
    output wire          s1_axis_tready,
    input  wire          s1_axis_tlast,

    // AXI4-Stream Master output: flush result to DMA
    output wire  [767:0] m_axis_tdata,
    output wire          m_axis_tvalid,
    input  wire          m_axis_tready,
    output wire          m_axis_tlast
);

    Top u_top (
        .aclk           (aclk),
        .aresetn        (aresetn),

        .s0_axis_tdata  (s0_axis_tdata),
        .s0_axis_tvalid (s0_axis_tvalid),
        .s0_axis_tready (s0_axis_tready),
        .s0_axis_tlast  (s0_axis_tlast),

        .s1_axis_tdata  (s1_axis_tdata),
        .s1_axis_tvalid (s1_axis_tvalid),
        .s1_axis_tready (s1_axis_tready),
        .s1_axis_tlast  (s1_axis_tlast),

        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tlast   (m_axis_tlast)
    );

endmodule