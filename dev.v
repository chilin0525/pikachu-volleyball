`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Dept. of Computer Science, National Chiao Tung University
// Engineer: Chun-Jen Tsai 
// 
// Create Date: 2018/12/11 16:04:41
// Design Name: 
// Module Name: lab9
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: A circuit that show the animation of a fish swimming in a seabed
//              scene on a screen through the VGA interface of the Arty I/O card.
// 
// Dependencies: vga_sync, clk_divider, sram 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module lab10(
    input  clk,
    input  reset_n,
    input  [3:0] usr_btn,
    output [3:0] usr_led,
    
    // VGA specific I/O ports
    output VGA_HSYNC,
    output VGA_VSYNC,
    output [3:0] VGA_RED,
    output [3:0] VGA_GREEN,
    output [3:0] VGA_BLUE
    );

// Declare system variables
reg  [31:0] fish_clock;
reg  [31:0] fish_clock2;
wire [9:0]  pos;
wire [9:0]  pos2;
wire        fish_region;
wire        fish_region2;

// declare SRAM control signals
wire [16:0] sram_addr;
wire [16:0] sram_addr2;
wire [16:0] sram_addr3;
wire [11:0] data_in;
wire [11:0] data_out;
wire [11:0] data_out2;
wire [11:0] data_out3;
wire        sram_we, sram_en;

// General VGA control signals
wire vga_clk;         // 50MHz clock for VGA control
wire video_on;        // when video_on is 0, the VGA controller is sending
                      // synchronization signals to the display device.
  
wire pixel_tick;      // when pixel tick is 1, we must update the RGB value
                      // based for the new coordinate (pixel_x, pixel_y)
  
wire [9:0] pixel_x;   // x coordinate of the next pixel (between 0 ~ 639) 
wire [9:0] pixel_y;   // y coordinate of the next pixel (between 0 ~ 479)
  
reg  [11:0] rgb_reg;  // RGB value for the current pixel
reg  [11:0] rgb_next; // RGB value for the next pixel
  
// Application-specific VGA signals
reg  [17:0] pixel_addr;
reg  [17:0] pixel_addr2;
reg  [17:0] pixel_addr3;
reg  [17:0] background_for_pixel_addr;

// Declare the video buffer size
localparam VBUF_W = 320; // video buffer width
localparam VBUF_H = 240; // video buffer height

// Set parameters for the fish images
localparam FISH_VPOS2   = 70;  // Vertical location of the fish in the sea image.                top 
localparam FISH_VPOS   =  130; // Vertical location of the fish in the sea image. data2         down
localparam FISH_W      =  78;  // Width of the fish.  
localparam FISH_H      =  79;  // Height of the fish.

//localparam FISH_H      = 44; // Height of the fish.
reg [17:0] fish_addr[0:2];   // Address array for up to 8 fish images.



// Initializes the fish images starting addresses.
// Note: System Verilog has an easier way to initialize an array,
//       but we are using Verilog 2001 :(
initial begin
  fish_addr[0] = VBUF_W*VBUF_H + 18'd0;         /* Addr for fish image #1 */
  fish_addr[1] = VBUF_W*VBUF_H + FISH_W*FISH_H; /* Addr for fish image #2 */
  fish_addr[2] = VBUF_W*VBUF_H + FISH_W*FISH_H*2; /* Addr for fish image #2 */
  fish_addr[3] = VBUF_W*VBUF_H + FISH_W*FISH_H*3; /* Addr for fish image #2 */
  fish_addr[4] = VBUF_W*VBUF_H + FISH_W*FISH_H*4; /* Addr for fish image #2 */
  fish_addr[5] = VBUF_W*VBUF_H + FISH_W*FISH_H*5; /* Addr for fish image #2 */
  fish_addr[6] = VBUF_W*VBUF_H + FISH_W*FISH_H*6; /* Addr for fish image #2 */
  fish_addr[7] = VBUF_W*VBUF_H + FISH_W*FISH_H*7; /* Addr for fish image #2 */

end



// Instiantiate the VGA sync signal generator
vga_sync vs0(
  .clk(vga_clk), .reset(~reset_n), .oHS(VGA_HSYNC), .oVS(VGA_VSYNC),
  .visible(video_on), .p_tick(pixel_tick),
  .pixel_x(pixel_x), .pixel_y(pixel_y)
);
// oHS : Ready to get next pixel?
// oVS : Is it active scan line period or sync period?
// ??visible?? is false, the RGB output to the monitor MUST be all zeros

clk_divider#(2) clk_divider0(
  .clk(clk),
  .reset(~reset_n),
  .clk_out(vga_clk)
);



// ------------------------------------------------------------------------
// The following code describes an initialized SRAM memory block that
// stores a 320x240 12-bit seabed image, plus two 64x32 fish images.
sram #(.DATA_WIDTH(12), .ADDR_WIDTH(18), .RAM_SIZE(VBUF_W*VBUF_H))
  ram0 (.clk(clk), .we(sram_we), .en(sram_en),
          .addr(sram_addr), .data_i(data_in), .data_o(data_out));

sram2 #(.DATA_WIDTH(12), .ADDR_WIDTH(18), .RAM_SIZE(FISH_W*FISH_H))
  ram1 (.clk(clk), .we(sram_we), .en(sram_en),
          .addr(sram_addr2), .data_i(data_in), .data_o(data_out2));

sram3 #(.DATA_WIDTH(12), .ADDR_WIDTH(18), .RAM_SIZE(FISH_W*FISH_H))
  ram2 (.clk(clk), .we(sram_we), .en(sram_en),
          .addr(sram_addr3), .data_i(data_in), .data_o(data_out3));


assign sram_we = usr_btn[0]; // In this demo, we do not write the SRAM. However, if
                             // you set 'sram_we' to 0, Vivado fails to synthesize
                             // ram0 as a BRAM -- this is a bug in Vivado.
assign sram_en = 1;          // Here, we always enable the SRAM block.
assign sram_addr = pixel_addr;
assign sram_addr2 = pixel_addr2;
assign sram_addr3 = pixel_addr3;

assign data_in = 12'h000; // SRAM is read-only so we tie inputs to zeros.
// End of the SRAM memory block.
// ------------------------------------------------------------------------

// VGA color pixel generator
assign {VGA_RED, VGA_GREEN, VGA_BLUE} = rgb_reg;
// RGB value for the current pixel



// ------------------------------------------------------------------------
// An animation clock for the motion of the fish, upper bits of the
// fish clock is the "x position of the fish" on the VGA screen.
// Note that the fish will move one screen pixel every 2^20 clock cycles,
// or 10.49 msec
// pos [9:0]

assign pos  = fish_clock[31:20]; 
assign pos2 = fish_clock2[31:20]; 
// "fish_clock" is the position of fish
// the x position of the right edge of the fish image in the 640x480 VGA screen
// localparam VBUF_W = 320  video buffer width
// localparam FISH_W = 64;  Width of the fish.

always @(posedge clk) begin
  if (~reset_n || fish_clock[31:21] > VBUF_W + FISH_W)
    // VBUF_W + FISH_W -> all fish iver screen then clear position to 0
    fish_clock <= 0;
  else begin
    if(usr_btn[3])begin
      fish_clock <= fish_clock + 5; 
    end else if(usr_btn[2]) begin
      fish_clock <= fish_clock + 1;
    end else begin
      fish_clock <= fish_clock ;        
    end    
  end
end
// End of the animation clock code.
// ------------------------------------------------------------------------

always @(posedge clk) begin
  if (~reset_n || fish_clock2[31:21] > VBUF_W + FISH_W)
    // VBUF_W + FISH_W -> all fish iver screen then clear position to 0
    fish_clock2 <= 0;
  else begin
    if(usr_btn[1])begin
      fish_clock2 <= fish_clock2 + 5; 
    end else if(usr_btn[2]) begin
      fish_clock2 <= fish_clock2 + 1;
    end else begin
      fish_clock2 <= fish_clock2;        
    end    
  end
end
// End of the animation clock code.
// ------------------------------------------------------------------------


integer flag_fish_region = 0;
integer flag_fish_region2 = 0;
integer y_rec = 0;
// ################### (AGU) ####################
// ------------------------------------------------------------------------
// Video frame buffer address generation unit (AGU) with scaling control
// Note that the width x height of the fish image is 64x32, when scaled-up
// on the screen, it becomes 128x64. 'pos' specifiebecomes 128x64. 'pos' specifies the right edge of the fish image.
assign fish_region =
  pixel_y >= (FISH_VPOS<<1) && pixel_y < (FISH_VPOS+FISH_H)<<1 && (pixel_x + 155) >= pos && pixel_x < pos + 1;

assign fish_region2 =
  pixel_y >= (FISH_VPOS2<<1) && pixel_y < (FISH_VPOS2+FISH_H)<<1 && (pixel_x + 155) >= pos2 && pixel_x < pos2 + 1;

always @ (posedge clk) begin
  if (~reset_n) begin
    pixel_addr <= 0;
    pixel_addr2 <= 0;
    pixel_addr3 <= 0; 
    flag_fish_region <= 0;
    flag_fish_region2 <= 0;
    background_for_pixel_addr <= 0;
    y_rec <= 0;
  end else if (fish_region && fish_region2)begin
    pixel_addr3 <= ((pixel_y>>1)-FISH_VPOS2)*FISH_W + ((pixel_x +(FISH_W*2-1)-pos2)>>1); 
    pixel_addr2 <= ((pixel_y>>1)-FISH_VPOS)*FISH_W  + ((pixel_x +(FISH_W*2-1)-pos)>>1);
    pixel_addr  <= (pixel_y >> 1) * VBUF_W + (pixel_x >> 1);
    flag_fish_region <= 1;
    flag_fish_region2 <= 1;
    y_rec <= pixel_y;
  end else if (fish_region)begin
    pixel_addr3 <= 0; 
    pixel_addr2 <= ((pixel_y>>1)-FISH_VPOS)*FISH_W + ((pixel_x +(FISH_W*2-1)-pos)>>1);
    pixel_addr  <= (pixel_y >> 1) * VBUF_W + (pixel_x >> 1);
    flag_fish_region <= 1;
    flag_fish_region2 <= 0;
  end else if (fish_region2)begin
    pixel_addr3 <= ((pixel_y>>1)-FISH_VPOS2)*FISH_W + ((pixel_x +(FISH_W*2-1)-pos2)>>1);
    pixel_addr2 <= 0;
    pixel_addr  <= (pixel_y >> 1) * VBUF_W + (pixel_x >> 1);
    flag_fish_region <= 0;
    flag_fish_region2 <= 1;
  end else begin
    // Scale up a 320x240 image for the 640x480 display.
    // (pixel_x, pixel_y) ranges from (0,0) to (639, 479)
    pixel_addr <= (pixel_y >> 1) * VBUF_W + (pixel_x >> 1);
    pixel_addr2 <= 0;
    pixel_addr3 <= 0; 
    flag_fish_region <= 0;
    flag_fish_region2 <= 0;
    // localparam VBUF_W = 320; // video buffer width
  end
end
// End of the AGU code.
// ------------------------------------------------------------------------


// ------------------------------------------------------------------------
// Send the video data in the sram to the VGA controller
always @(posedge clk) begin
  if (pixel_tick) rgb_reg <= rgb_next;
end
// when pixel tick is 1, we must update the RGB value
// based for the new coordinate (pixel_x, pixel_y)

always @(*) begin
  if (~video_on)
    rgb_next <= 12'h000; // Synchronization period, must set RGB values to zero.
  else
    if(flag_fish_region && flag_fish_region2)begin
      if(data_out2!=12'h0f0) rgb_next <= data_out2;
      else  begin
            if(y_rec>220) begin
                rgb_next <= data_out;
            end else begin
                if(data_out3==12'h0f0) rgb_next <= data_out;
                else rgb_next <= data_out3;
            end
      end
    end else if(flag_fish_region)begin
      if(data_out2==12'h0f0) rgb_next <= data_out;
      else rgb_next <= data_out2;
    end else if(flag_fish_region2)begin
      if(data_out3==12'h0f0) rgb_next <= data_out;
      else rgb_next <= data_out3;
    end else begin
      rgb_next <= data_out;
    end
    //rgb_next = data_out; // RGB value at (pixel_x, pixel_y)
end
// End of the video data display code.
// ------------------------------------------------------------------------


endmodule
