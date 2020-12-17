`timescale 1ns / 1ps

module lab10(
    input  clk,
    input  reset_n,
    input  [3:0] usr_btn,
    input  [3:0] usr_sw,
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
reg [9:0]  pos_right_x;
reg [9:0]  pos_right_y;
reg [9:0]  pos_left_x;
reg [9:0]  pos_left_y;
reg [9:0]  pos_ball_x;
reg [9:0]  pos_ball_y;

reg [9:0]  velocity_right_x;
reg [9:0]  velocity_right_y;
reg [9:0]  velocity_left_x;
reg [9:0]  velocity_left_y;
reg [9:0]  velocity_ball_x;
reg [9:0]  velocity_ball_y;



wire        fish_region;

// declare SRAM control signals
wire [16:0] sram_addr;
wire [16:0] sram_addr_left;
wire [16:0] sram_addr_right;
wire [16:0] sram_addr_ball;

wire [11:0] data_in;
wire [11:0] data_out;
wire [11:0] data_out_left;
wire [11:0] data_out_right;
wire [11:0] data_out_ball;

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
reg  [17:0] pixel_addr_left;
reg  [17:0] pixel_addr_right;
reg  [17:0] pixel_addr_ball;

localparam[4:0] GRAVITY=1;

localparam[4:0] S_MAIN_INIT=0,
                S_MAIN_SET_POSITION_X=1,
                S_MAIN_IDLE=2,
                S_MAIN_SET_VELOCITY_X=3,
                S_MAIN_SET_POSITION_Y=4,
                S_MAIN_SET_VELOCITY_Y=5,
                S_MAIN_FIX_POSITION_X=6,
                S_MAIN_FIX_POSITION_Y=7,
                S_MAIN_SET_BALL_POSITION=8,
                S_MAIN_SET_BALL_VELOCITY=9;
                
                
                
                
reg [4:0] P,P_next;
reg [31:0]clock;

wire finish_idle;
// Declare the video buffer size
localparam VBUF_W = 320; // video buffer width
localparam VBUF_H = 240; // video buffer height

// Set parameters for the fish images
localparam FISH_VPOS   = 64; // Vertical location of the fish in the sea image.
localparam FISH_W      = 78; // Width of the fish.
localparam FISH_H      = 79; // Height of the fish.

// Initializes the fish images starting addresses.
// Note: System Verilog has an easier way to initialize an array,
//       but we are using Verilog 2001 :(

// Instiantiate the VGA sync signal generator
vga_sync vs0(
  .clk(vga_clk), .reset(~reset_n), .oHS(VGA_HSYNC), .oVS(VGA_VSYNC),
  .visible(video_on), .p_tick(pixel_tick),
  .pixel_x(pixel_x), .pixel_y(pixel_y)
);

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
sram_fish1 #(.DATA_WIDTH(12), .ADDR_WIDTH(18), .RAM_SIZE(78*79))
  ram1 (.clk(clk), .we(sram_we), .en(sram_en),
          .addr(sram_addr_left), .data_i(data_in), .data_o(data_out_left));
sram_fish2 #(.DATA_WIDTH(12), .ADDR_WIDTH(18), .RAM_SIZE(78*79))
  ram2 (.clk(clk), .we(sram_we), .en(sram_en),
          .addr(sram_addr_right), .data_i(data_in), .data_o(data_out_right));
sram_fish3 #(.DATA_WIDTH(12), .ADDR_WIDTH(18), .RAM_SIZE(55*55))
  ram3 (.clk(clk), .we(sram_we), .en(sram_en),
          .addr(sram_addr_ball), .data_i(data_in), .data_o(data_out_ball));

assign sram_we = usr_sw[3]; // In this demo, we do not write the SRAM. However, if
                             // you set 'sram_we' to 0, Vivado fails to synthesize
                             // ram0 as a BRAM -- this is a bug in Vivado.
assign sram_en = 1;          // Here, we always enable the SRAM block.
assign sram_addr_left = pixel_addr_left;
assign sram_addr_right = pixel_addr_right;
assign sram_addr_ball = pixel_addr_ball;

assign sram_addr = pixel_addr;
assign data_in = 12'h000; // SRAM is read-only so we tie inputs to zeros.
// End of the SRAM memory block.
// ------------------------------------------------------------------------

// VGA color pixel generator
assign {VGA_RED, VGA_GREEN, VGA_BLUE} = rgb_reg;
reg [4:0]mode=0;
wire ball_region;
// ------------------------------------------------------------------------

always@(posedge clk)begin
if(~reset_n)mode<=0;
else if(P==S_MAIN_INIT)mode<=mode==5?0:mode+1;
end


always@(posedge clk)begin
if(~reset_n)P<=S_MAIN_INIT;
else P<=P_next;
end

always@(*)begin

case(P)
  S_MAIN_INIT:
     P_next<=S_MAIN_SET_VELOCITY_X;
  S_MAIN_SET_VELOCITY_X:
     P_next<=S_MAIN_SET_VELOCITY_Y;
  S_MAIN_SET_VELOCITY_Y:
     P_next<=S_MAIN_SET_BALL_VELOCITY;
  S_MAIN_SET_BALL_VELOCITY:
     P_next<=S_MAIN_SET_POSITION_X;
  S_MAIN_SET_POSITION_X:
     P_next<=S_MAIN_SET_POSITION_Y;
  S_MAIN_SET_POSITION_Y:
     P_next<=S_MAIN_SET_BALL_POSITION;
  S_MAIN_SET_BALL_POSITION:
     P_next<=S_MAIN_FIX_POSITION_X;
  S_MAIN_FIX_POSITION_X:
     P_next<=S_MAIN_FIX_POSITION_Y;
  S_MAIN_FIX_POSITION_Y:
     P_next<=S_MAIN_IDLE;
  S_MAIN_IDLE:
     if(finish_idle==1)P_next<=S_MAIN_INIT;
     else P_next=S_MAIN_IDLE;
  

endcase
end

assign finish_idle=(clock==50000)?1:0;

always@(posedge clk)begin
clock<=clock==300000?0:clock+1;
end

always@(posedge clk)begin
if(~reset_n)begin 
   
  end
else if(P==S_MAIN_SET_VELOCITY_X)begin

if(usr_btn[0])begin velocity_right_x<=1; velocity_left_x<=1;end 
else if(usr_btn[2])velocity_right_x<=0-1;
else begin velocity_right_x<=0; velocity_left_x<=0; end

end
else if(P==S_MAIN_SET_VELOCITY_Y&&mode==5)begin

if(usr_btn[1]&&pos_right_y==401)velocity_right_y<=21;
else if (pos_right_y==401)velocity_right_y<=0;
else velocity_right_y<=(velocity_right_y==(-21))?0:velocity_right_y-GRAVITY;

end
else if(P==S_MAIN_SET_BALL_VELOCITY&&mode==5)begin

velocity_ball_y<=velocity_ball_y-GRAVITY;

end
else if(P==S_MAIN_FIX_POSITION_X)begin
  if(pos_ball_x>613||pos_ball_x<27)begin  velocity_ball_x<=(-1)* velocity_ball_x; end
  else if(pos_ball_x>=285 && pos_ball_x<=361 && pos_ball_y>260) begin velocity_ball_x<=(-1)* velocity_ball_x; end
end
else if(P==S_MAIN_FIX_POSITION_Y&&mode==5)begin
  if(pos_ball_y>413||pos_ball_y<27)begin velocity_ball_y <= (-1)* velocity_ball_y;  end
  else if(pos_ball_x>=285 && pos_ball_x<=361 && pos_ball_y>250 && pos_ball_y<270) begin velocity_ball_y <= (-1)* velocity_ball_y; end
 end

end


initial begin 
  pos_left_x<=59; 
  pos_left_y<=401; 
  pos_right_x<=582; 
  pos_right_y<=401;
  pos_ball_x<=320;
  pos_ball_y<=28;
  
  
  velocity_right_x<=0;
  velocity_right_y<=0;
  velocity_left_x<=0;
  velocity_left_y<=0;
  velocity_ball_x<=2;
  velocity_ball_y<=0;
end

always@(posedge clk)begin

 if(~reset_n)begin 

  end
  else if(P==S_MAIN_SET_POSITION_X)begin
  pos_right_x<=pos_right_x+velocity_right_x;
  pos_left_x <=pos_left_x +velocity_left_x;
  pos_ball_x<=pos_ball_x+velocity_ball_x;
  end
  else if(P==S_MAIN_SET_POSITION_Y&&mode==5)begin
  pos_right_y<=pos_right_y-velocity_right_y;
  end
  else if(P==S_MAIN_SET_BALL_POSITION&&mode==5)begin
  pos_ball_y<=pos_ball_y-velocity_ball_y;
  end
  else if(P==S_MAIN_FIX_POSITION_X)begin
  if(pos_right_x>602)pos_right_x<=602;
  else if(pos_right_x<361)pos_right_x<=361;
  
  if(pos_ball_x>613)pos_ball_x<=613;
  else if(pos_ball_x<27)pos_ball_x<=27;

  if(pos_left_x>279)pos_left_x<=279;
  else if(pos_left_x<60)pos_left_x<=60;
  end
  else if(P==S_MAIN_FIX_POSITION_Y&&mode==5)begin
  //pos_right_y<=pos_right_y;
  
  if(pos_ball_y>413)begin pos_ball_y<=413;  end
  else if(pos_ball_y<27)begin pos_ball_y<=27;  end
  end
end


wire fish_region1 ;

assign fish_region =
            pixel_y>= (pos_left_y-39) && pixel_y <=( pos_left_y+39)&&
           pixel_x>= (pos_left_x-39) && pixel_x <=( pos_left_x +38);
assign fish_region1 =
           pixel_y>= (pos_right_y-39) && pixel_y <=( pos_right_y+39) &&
           pixel_x>= (pos_right_x-39) && pixel_x <=( pos_right_x +38);
assign ball_region =
           pixel_y>= (pos_ball_y-27) && pixel_y <=( pos_ball_y+27) &&
           pixel_x>= (pos_ball_x-27) && pixel_x <=( pos_ball_x+27);

always @ (posedge clk) begin
  if (~reset_n)
    pixel_addr <= 0;
  else if(P==S_MAIN_IDLE)
    // Scale up a 320x240 image for the 640x480 display.
    // (pixel_x, pixel_y) ranges from (0,0) to (639, 479)
    pixel_addr <= (pixel_y >> 1) * VBUF_W + (pixel_x >> 1);
end

always @ (posedge clk) begin
  if (fish_region&&P==S_MAIN_IDLE)
    pixel_addr_left <= ((pixel_y)-pos_left_y+39)*FISH_W +(pixel_x-pos_left_x+39);
  else
    pixel_addr_left <=0;
end

always @ (posedge clk) begin
  if (fish_region1&&P==S_MAIN_IDLE)
    pixel_addr_right <= ((pixel_y)-pos_right_y+39)*FISH_W+(pixel_x-pos_right_x+39);
  else
    pixel_addr_right <=0;
end
always @ (posedge clk) begin
  if (ball_region&&P==S_MAIN_IDLE)
    pixel_addr_ball <= ((pixel_y)-pos_ball_y+27)*55+(pixel_x-pos_ball_x+27);
  else
    pixel_addr_ball <=0;
end
// End of the AGU code.
// ------------------------------------------------------------------------

// ------------------------------------------------------------------------
// Send the video data in the sram to the VGA controller
always @(posedge clk) begin
  if (pixel_tick&&P==S_MAIN_IDLE) rgb_reg <= rgb_next;
end

always @(*) begin
  if (~video_on&&P==S_MAIN_IDLE)
    rgb_next <= 12'h000; // Synchronization period, must set RGB values to zero.
    else if(ball_region&&fish_region&&data_out_ball!=12'h0F0&&P==S_MAIN_IDLE)rgb_next<=data_out_ball;
    else if(ball_region&&fish_region1&&data_out_ball!=12'h0F0&&P==S_MAIN_IDLE)rgb_next<=data_out_ball;   
    else if(ball_region&&fish_region&&data_out_left!=12'h0F0&&P==S_MAIN_IDLE)rgb_next<=data_out_left;
    else if(ball_region&&fish_region1&&data_out_right!=12'h0F0&&P==S_MAIN_IDLE)rgb_next<=data_out_right;   
    else if(fish_region&&data_out_left!=12'h0F0&&P==S_MAIN_IDLE)rgb_next<=data_out_left;
    else if(fish_region1&&data_out_right!=12'h0F0&&P==S_MAIN_IDLE)rgb_next<=data_out_right;
    else if(ball_region&&data_out_ball!=12'h0F0&&P==S_MAIN_IDLE)rgb_next<=data_out_ball;    
    else rgb_next <= data_out;
end
// End of the video data display code.
// ------------------------------------------------------------------------

endmodule
