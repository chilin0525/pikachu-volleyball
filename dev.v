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

reg [9:0]  pos_right_x;
reg [9:0]  pos_right_y;
reg [9:0]  pos_left_x;
reg [9:0]  pos_left_y;
reg [9:0]  pos_predict_x;
reg [9:0]  pos_predict_y;
reg [9:0]  pos_ball_x;
reg [9:0]  pos_ball_y;
reg [9:0]  pos_score_x ;
reg [9:0]  pos_score_y ;
reg [9:0]  pos_score2_x ;
reg [9:0]  pos_score2_y ;

reg [9:0] score_l;
reg [9:0] score_r;
reg [40:0] score_idx[3:0];

reg signed [31:0]  velocity_right_x;
reg signed [31:0]  velocity_right_y;
reg signed [31:0]  velocity_left_x;
reg signed [31:0]  velocity_left_y;
reg signed [31:0]  velocity_ball_x;
reg signed [31:0]  velocity_ball_y;


reg signed [31:0] right_diff_x;
reg signed [31:0] right_diff_y;
reg signed [31:0] left_diff_x;
reg signed [31:0] left_diff_y;

reg [31:0] right_square_x;
reg [31:0] right_square_y;
reg [31:0] left_square_x;
reg [31:0] left_square_y;
reg [31:0] right_sum;
reg [31:0] left_sum;

reg [31:0] diff_right;
reg [31:0] diff_left;

reg [31:0]  clock1;
wire        fish_region;
wire        score_region;
wire        score_region2;

// declare SRAM control signals
wire [16:0] sram_addr;
wire [16:0] sram_addr_left;
wire [16:0] sram_addr_right;
wire [16:0] sram_addr_ball;
wire [16:0] sram_addr_score;
wire [16:0] sram_addr_score2;
wire finish;
wire [11:0] data_in;
wire [11:0] data_out;
wire [11:0] data_out_left;
wire [11:0] data_out_right;
wire [11:0] data_out_ball;
wire [11:0] data_out_score;
wire [11:0] data_out_score2;

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
reg  [30:0] pixel_addr_ball;
reg  [17:0] pixel_addr_score;
reg  [17:0] pixel_addr_score2;

reg [30:0] pixel_ball_rec[0:3];
reg [30:0] ball_pic_count;

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
                S_MAIN_SET_BALL_VELOCITY=9,
                S_MAIN_DETECT=10,
                S_MAIN_CALCULATE=11,
                S_MAIN_CALCULATE1=12,
                S_MAIN_CALCULATE2=13,
                S_MAIN_DELAY=14,
                S_MAIN_PREDICT=15,
                S_MAIN_ASSIGN_ROBOT=16,
                S_MAIN_FIX=17,
                S_MAIN_DELAY_ROUND=18,
                S_MAIN_FINISH=19;
                
                
                
                
                
reg [4:0] P,P_next;
reg [31:0]clock;
reg [31:0]idx;
wire predict_done;

assign predict_done=idx==200?1:0;

wire finish_idle;
reg round_over;
reg[31:0]idx1;
wire finish_delay_round;

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
sram_fish3 #(.DATA_WIDTH(12), .ADDR_WIDTH(18), .RAM_SIZE(55*55*4))
  ram3 (.clk(clk), .we(sram_we), .en(sram_en),
          .addr(sram_addr_ball), .data_i(data_in), .data_o(data_out_ball));
ram_score #(.DATA_WIDTH(12), .ADDR_WIDTH(18), .RAM_SIZE(51*51*8))
  ram4 (.clk(clk), .we(sram_we), .en(sram_en),
          .addr(sram_addr_score), .data_i(data_in), .data_o(data_out_score));
ram_score2 #(.DATA_WIDTH(12), .ADDR_WIDTH(18), .RAM_SIZE(51*51*8))
  ram5 (.clk(clk), .we(sram_we), .en(sram_en),
          .addr(sram_addr_score2), .data_i(data_in), .data_o(data_out_score2));
          
assign usr_led[0]=(P==S_MAIN_DELAY)?1:0;
assign sram_we = usr_sw[3]; // In this demo, we do not write the SRAM. However, if
                             // you set 'sram_we' to 0, Vivado fails to synthesize
                             // ram0 as a BRAM -- this is a bug in Vivado.
assign sram_en = 1;          // Here, we always enable the SRAM block.
assign sram_addr_left   = pixel_addr_left;
assign sram_addr_right  = pixel_addr_right;
assign sram_addr_ball   = pixel_addr_ball;
assign sram_addr_score  = pixel_addr_score;
assign sram_addr_score2  = pixel_addr_score2;

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
    if(~reset_n)P<=S_MAIN_DELAY;
    else P<=P_next;
end

reg [2:0]bool;
reg flag_1 ;


always@(posedge clk)begin
    // ############################################################################### 410
    if(~reset_n)begin bool<=2; flag_1<=1;  end 
    if(P==S_MAIN_IDLE)begin
        if(pos_ball_y>410)begin
            round_over<=1;
            if(pos_ball_x>320)begin 
                bool<=2; 
                if(flag_1==1)begin score_l<=score_l+1;flag_1 <= 0;end
            end else begin 
                bool<=1;
                if(flag_1==1)begin score_r<=score_r+1;flag_1 <= 0;end
            end
            
        end else begin bool<=0;round_over<=0;end
    end else if(P == S_MAIN_CALCULATE) begin
        flag_1 <= 1;
    end
end

always@(*)begin
  case(P)
    S_MAIN_DELAY:
      if(finish) P_next<=S_MAIN_INIT;
      else P_next<=S_MAIN_DELAY;
    S_MAIN_INIT:
    if(score_r==7||score_l==7)P_next<=S_MAIN_FINISH;
     else  P_next<=S_MAIN_SET_VELOCITY_X;
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
      P_next<=S_MAIN_CALCULATE;
    S_MAIN_CALCULATE:
      P_next<= S_MAIN_CALCULATE1;
    S_MAIN_CALCULATE1:
      P_next<=S_MAIN_CALCULATE2;
    S_MAIN_CALCULATE2:
      P_next<=S_MAIN_DETECT;
    S_MAIN_DETECT:
      P_next<=S_MAIN_PREDICT;
    S_MAIN_PREDICT:
      if(predict_done)P_next<=S_MAIN_ASSIGN_ROBOT;
      else P_next<=S_MAIN_FIX;
    S_MAIN_FIX:
      P_next<=S_MAIN_ASSIGN_ROBOT;     
    S_MAIN_ASSIGN_ROBOT:
      P_next<=S_MAIN_IDLE;
    S_MAIN_IDLE:
      if(finish_idle==1)P_next<=S_MAIN_INIT;
      else if(round_over==1)P_next<=S_MAIN_DELAY;
      else P_next=S_MAIN_IDLE;
    S_MAIN_FINISH:
    P_next<=S_MAIN_FINISH;
    
  endcase
end

assign finish=(clock1==200000000)?1:0;
assign finish_delay_round=(idx1==200000000)?1:0;
assign finish_idle=(clock==50000)?1:0;

// delay for start game 
always@(posedge clk)begin
  if(P==S_MAIN_DELAY)clock1<=clock1+1;
  else clock1<=0;
end

// delay for end game 
always@(posedge clk)begin
  clock<=clock==300000?0:clock+1;
end

always@(posedge clk)begin
 if(~reset_n)idx<=0;
 else if(P==S_MAIN_PREDICT)idx<=idx+1;
 else idx<=0;
 
end

always@(posedge clk)begin
 if(~reset_n)idx1<=0;
 else if(P==S_MAIN_DELAY_ROUND)idx1<=idx1+1;
 else idx1<=0;
 
end

always@(posedge clk)begin

 if(P==S_MAIN_PREDICT)begin
 pos_predict_x<=pos_predict_x+velocity_ball_x;
 end
 else if(P==S_MAIN_FIX)begin
 if(pos_predict_x<27)pos_predict_x<=54-pos_predict_x;
 else if(pos_predict_x>613)pos_predict_x<=1226-pos_predict_x;
 end
 else if(P==S_MAIN_CALCULATE)begin
 pos_predict_x<=pos_ball_x;
 end
 //pos_predict_y<=pos_predict_y+velocity_ball_y;
 end
 
 reg [5:0]mode1;
 
 always@(posedge clk)begin
 mode1<=mode1==2?0:mode1+1;
 end
// always@(posedge clk)begin
//   if(~reset_n || ball_pic_count>=3000000) ball_pic_count <= 0;
//   else ball_pic_count <= ball_pic_count + 1;
// end

always@(posedge clk)begin
  if(~reset_n)begin 
   
  end else if(P==S_MAIN_SET_VELOCITY_X)begin
    if(usr_btn[0])begin velocity_right_x<=1;/* velocity_left_x<=1; */end
    else if(usr_btn[2]) begin velocity_right_x<=0-1;/* velocity_left_x<=0-1; */end 
    else begin velocity_right_x<=0; /*velocity_left_x<=0;*/ end 
    // set position of pikachu 
  end else if(P==S_MAIN_SET_VELOCITY_Y&&mode==5)begin
    if(usr_btn[1]&&pos_right_y==401)velocity_right_y<=21;
    else if (pos_right_y==401)velocity_right_y<=0;
    else velocity_right_y<=(velocity_right_y==(-21))?0:velocity_right_y-GRAVITY;
    
    if(pos_left_y==401&&velocity_ball_x==0&&pos_ball_y>220&&pos_ball_y<300&&left_diff_x<=30&&left_diff_x>=(-30)&&velocity_ball_y<0)velocity_left_y<=21;
    else if (pos_left_y==401)velocity_left_y<=0;
    else velocity_left_y<=(velocity_left_y==(-21))?0:velocity_left_y-GRAVITY;
  end else if(P==S_MAIN_SET_BALL_VELOCITY&&mode==5)begin
    velocity_ball_y<=velocity_ball_y-GRAVITY;
    // sub gravity 
  end else if(P==S_MAIN_FIX_POSITION_X)begin
    if(pos_ball_x>613 || pos_ball_x<27) begin velocity_ball_x<=(-1)* velocity_ball_x; end
    else if(pos_ball_x>=290 && pos_ball_x<=350 && pos_ball_y>250) begin velocity_ball_x<=(-1)* velocity_ball_x; end
    // rebound for ball 
  end else if(P==S_MAIN_FIX_POSITION_Y&&mode==5)begin
    if(pos_ball_y>413 || pos_ball_y<27) begin velocity_ball_y<=(-1)* velocity_ball_y; end
    else if(pos_ball_x>=290 && pos_ball_x<=350 && pos_ball_y>250 && velocity_ball_y<-20) begin velocity_ball_y <= (-1)* velocity_ball_y; end
    else if(pos_ball_x>=290 && pos_ball_x<=350 && pos_ball_y>250 && pos_ball_y<270 && velocity_ball_y<0) begin velocity_ball_y <= (-1)* velocity_ball_y; end
    // rebound for ball 
  end else if(P==S_MAIN_DETECT)begin
    // ball - right_x
    if(right_sum<=3600&&usr_btn[3]&&usr_btn[1])begin velocity_ball_y<=22; velocity_ball_x<=-3;end
    else if(right_sum<=3600&&usr_btn[3]&&usr_btn[2])begin velocity_ball_y<=-12; velocity_ball_x<=-4;end
    else if(right_sum<=3600&&right_diff_x<20&&right_diff_x>(-30))
      begin 
        // if(usr_btn[3]) begin velocity_ball_y<=22;  velocity_ball_x<=-4; end 
        // smash
        // else begin 
        //if(usr_btn[3]) begin  velocity_ball_y<=22; velocity_ball_x<=-4; end
         velocity_ball_y<=22;  velocity_ball_x<=0; 
        // end
      end
    else if(right_sum<=3600&&right_diff_x>=20)
      begin 
        //if(usr_btn[3]) begin  velocity_ball_y<=-18; velocity_ball_x<=-4; end
        // smash for 前面
        velocity_ball_y<=22; velocity_ball_x<=2;   
      end
    //else if(right_sum<=3600&&diff_right>=20)begin velocity_ball_y<=22;  velocity_ball_x<=0;  end
    else if(right_sum<=3600&&right_diff_x<=(-30))
      begin 
        //if(usr_btn[3]) begin velocity_ball_y<=-18;  velocity_ball_x<=-4; end 
        // smash for 尾巴
        velocity_ball_y<=22;  velocity_ball_x<=0-2;
      end
    //else if(right_sum<=3600&&diff_right<=-20)begin velocity_ball_y<=22;  velocity_ball_x<=0;  end
    if(left_sum<=3600&&pos_left_y<400)begin velocity_ball_y<=22; velocity_ball_x<=3;end
    else if(left_sum<=3600&&left_diff_x<30&&left_diff_x>(-20))begin velocity_ball_y<=22;  velocity_ball_x<=0;  end
    else if(left_sum<=3600&&left_diff_x>=30)begin velocity_ball_y<=22;  velocity_ball_x<=2;  end
    // else if(left_sum<=3600&&diff_left>=20)begin velocity_ball_y<=22;  velocity_ball_x<=0;  end
    else if(left_sum<=3600&&left_diff_x<=(-20))begin velocity_ball_y<=22;  velocity_ball_x<=0-2;  end
    // else if(left_sum<=3600&&diff_left<=-20)begin velocity_ball_y<=22;  velocity_ball_x<=0;  end

  end else if(P == S_MAIN_IDLE && P_next == S_MAIN_DELAY)begin
    velocity_right_x<=0;
    velocity_right_y<=0;
    velocity_left_x <=0;
    velocity_left_y <=0;
    velocity_ball_x <=0;
    velocity_ball_y <=0;
  end
  else if(P==S_MAIN_ASSIGN_ROBOT)begin
  if(pos_ball_x>pos_left_x&&pos_ball_x<320)velocity_left_x<=1;
  else if(pos_ball_x<pos_left_x&&pos_ball_x<320)velocity_left_x<=0-1;
  else if(pos_ball_x>320&&pos_left_x<120)velocity_left_x<=1;
  else if(pos_ball_x>320&&pos_left_x>120)velocity_left_x<=0-1;
  else velocity_left_x<=0;
  
  
 // else if(velocity_ball_x==0)velocity_left_x<=0;
  end
end


initial begin 
  pos_left_x  <=59; 
  pos_left_y  <=401; 
  pos_right_x <=582; 
  pos_right_y <=401;
  pos_ball_x  <=67;
  pos_ball_y  <=28;
  pos_score_x <=100; 
  pos_score_y <=100;
  pos_score2_x <=540; 
  pos_score2_y <=100; 

  velocity_right_x<=0;
  velocity_right_y<=0;
  velocity_left_x <=0;
  velocity_left_y <=0;
  velocity_ball_x <=0;
  velocity_ball_y <=0;

  pixel_ball_rec[0] <= 0;
  pixel_ball_rec[1] <= 3026;
  pixel_ball_rec[2] <= 6051;
  pixel_ball_rec[3] <= 9076;
  
  score_l <= 0;
  score_r <= 0;
  score_idx[0] <= 0;
  score_idx[1] <= 2601;
  score_idx[2] <= 5202;
  score_idx[3] <= 7803;
  score_idx[4] <= 10404;
  score_idx[5] <= 13006;
  score_idx[6] <= 15607;
  score_idx[7] <= 18208;
end

always@(posedge clk)begin
  if(P==S_MAIN_DELAY)begin 
    pos_ball_y<=28;
  end else if(P==S_MAIN_SET_POSITION_X)begin
    pos_right_x<=pos_right_x+velocity_right_x;
    pos_left_x<=pos_left_x+velocity_left_x;
    pos_ball_x<=pos_ball_x+velocity_ball_x;
  end else if(P==S_MAIN_SET_POSITION_Y&&mode==5)begin
    pos_right_y<=pos_right_y-velocity_right_y;
    pos_left_y<=pos_left_y-velocity_left_y;
  end else if(P==S_MAIN_SET_BALL_POSITION&&mode==5)begin
    pos_ball_y<=pos_ball_y-velocity_ball_y;
  end else if(P==S_MAIN_FIX_POSITION_X)begin
    if(pos_right_x>602)pos_right_x<=602;
    else if(pos_right_x<361)pos_right_x<=361;
    
    if(pos_left_x>281)pos_left_x<=281;
    else if(pos_left_x<39)pos_left_x<=39;
    
    if(pos_ball_x>613)pos_ball_x<=613;
    else if(pos_ball_x<27)pos_ball_x<=27;
  end else if(P==S_MAIN_FIX_POSITION_Y&&mode==5)begin
    if(pos_ball_y>413)begin pos_ball_y<=413;  end
    else if(pos_ball_y<27)begin pos_ball_y<=27;  end
  end else if(P==S_MAIN_CALCULATE)begin
    right_diff_x  <=pos_ball_x  - pos_right_x;
    right_diff_y  <=pos_ball_y  - pos_right_y;
    left_diff_x   <=pos_ball_x  - pos_left_x;
    left_diff_y   <=pos_ball_y  - pos_left_y;
    // calcalate distance of ball and pikachu
  end else if(P==S_MAIN_CALCULATE1)begin
    right_square_x<=right_diff_x* right_diff_x;
    right_square_y<=right_diff_y* right_diff_y;
    left_square_x <=left_diff_x * left_diff_x;
    left_square_y <=left_diff_y * left_diff_y;
    // diff**2
  end else if(P==S_MAIN_CALCULATE2)begin
    right_sum <=  right_square_x  + right_square_y;
    left_sum  <=  left_square_x   + left_square_y;
    // get distance
  end else if(P == S_MAIN_IDLE && P_next == S_MAIN_DELAY)begin
    pos_left_x  <=59; 
    pos_left_y  <=401; 
    pos_right_x <=582; 
    pos_right_y <=401;
    pos_ball_x  <=bool==2?67:573;
    pos_ball_y  <=27;
  end
end




wire fish_region1 ;
assign fish_region  =
            pixel_y>=(pos_left_y-39)  && pixel_y<=(pos_left_y+39) &&
            pixel_x>=(pos_left_x-39)  && pixel_x<=(pos_left_x +38);
assign fish_region1 =
            pixel_y>=(pos_right_y-39) && pixel_y<=(pos_right_y+39) &&
            pixel_x>=(pos_right_x-39) && pixel_x<=(pos_right_x +38);
assign ball_region  =
            pixel_y>=(pos_ball_y-27)  && pixel_y<=(pos_ball_y+27) &&
            pixel_x>=(pos_ball_x-27)  && pixel_x<=(pos_ball_x+27);
assign score_region =
            pixel_y>=(pos_score_y-25) && pixel_y<=(pos_score_y+25) &&
            pixel_x>=(pos_score_x-25) && pixel_x<=(pos_score_x+25);
assign score_region2 =
            pixel_y>=(pos_score2_y-25) && pixel_y<=(pos_score2_y+25) &&
            pixel_x>=(pos_score2_x-25) && pixel_x<=(pos_score2_x+25);



always @ (posedge clk) begin
  if (~reset_n)
    pixel_addr <= 0;
  else if((P==S_MAIN_IDLE||P==S_MAIN_DELAY))
    // Scale up a 320x240 image for the 640x480 display.
    // (pixel_x, pixel_y) ranges from (0,0) to (639, 479)
    pixel_addr <= (pixel_y >> 1) * VBUF_W + (pixel_x >> 1);
end

always @ (posedge clk) begin
  if (fish_region&&(P==S_MAIN_IDLE||P==S_MAIN_DELAY))
    pixel_addr_left <= ((pixel_y)-pos_left_y+39)*FISH_W +(pixel_x-pos_left_x+39);
  else if(P==S_MAIN_IDLE||P==S_MAIN_DELAY)
    pixel_addr_left <=0;
end

always @ (posedge clk) begin
  if (fish_region1&&(P==S_MAIN_IDLE||P==S_MAIN_DELAY))
    pixel_addr_right <= ((pixel_y)-pos_right_y+39)*FISH_W+(pixel_x-pos_right_x+39);
  else if(P==S_MAIN_IDLE||P==S_MAIN_DELAY)
    pixel_addr_right <=0;
end

always @ (posedge clk) begin
  if (ball_region&&(P==S_MAIN_IDLE||P==S_MAIN_DELAY))
    pixel_addr_ball <= ((pixel_y)-pos_ball_y+27)*55+(pixel_x-pos_ball_x+27)+pixel_ball_rec[pos_ball_x[8:7]];
    //pixel_addr_ball <= ((pixel_y)-pos_ball_y+27)*55+(pixel_x-pos_ball_x+27);
  else if(P==S_MAIN_IDLE||P==S_MAIN_DELAY)
    pixel_addr_ball <=0;
end

always @ (posedge clk) begin
  if (score_region&&(P==S_MAIN_IDLE||P==S_MAIN_DELAY))
      if(score_l==0)pixel_addr_score <= ((pixel_y)-pos_score_y+25)*51+(pixel_x-pos_score_x+25)+0;
      else if(score_l==1)pixel_addr_score <= ((pixel_y)-pos_score_y+25)*51+(pixel_x-pos_score_x+25)+2601;
      else if(score_l==2)pixel_addr_score <= ((pixel_y)-pos_score_y+25)*51+(pixel_x-pos_score_x+25)+5202;
      else if(score_l==3)pixel_addr_score <= ((pixel_y)-pos_score_y+25)*51+(pixel_x-pos_score_x+25)+7803;
      else if(score_l==4)pixel_addr_score <= ((pixel_y)-pos_score_y+25)*51+(pixel_x-pos_score_x+25)+10404;
      else if(score_l==5)pixel_addr_score <= ((pixel_y)-pos_score_y+25)*51+(pixel_x-pos_score_x+25)+13006;
      else if(score_l==6)pixel_addr_score <= ((pixel_y)-pos_score_y+25)*51+(pixel_x-pos_score_x+25)+15607;
      else if(score_l==7)pixel_addr_score <= ((pixel_y)-pos_score_y+25)*51+(pixel_x-pos_score_x+25)+18208;

  else if(P==S_MAIN_IDLE||P==S_MAIN_DELAY)
    pixel_addr_score <=0;
end
// for show score left

always @ (posedge clk) begin
  if (score_region2&&(P==S_MAIN_IDLE||P==S_MAIN_DELAY))
          if(score_r==0)pixel_addr_score2 <= ((pixel_y)-pos_score2_y+25)*51+(pixel_x-pos_score2_x+25)+0;
      else if(score_r==1)pixel_addr_score2 <= ((pixel_y)-pos_score2_y+25)*51+(pixel_x-pos_score2_x+25)+2601;
      else if(score_r==2)pixel_addr_score2 <= ((pixel_y)-pos_score2_y+25)*51+(pixel_x-pos_score2_x+25)+5202;
      else if(score_r==3)pixel_addr_score2 <= ((pixel_y)-pos_score2_y+25)*51+(pixel_x-pos_score2_x+25)+7803;
      else if(score_r==4)pixel_addr_score2 <= ((pixel_y)-pos_score2_y+25)*51+(pixel_x-pos_score2_x+25)+10404;
      else if(score_r==5)pixel_addr_score2 <= ((pixel_y)-pos_score2_y+25)*51+(pixel_x-pos_score2_x+25)+13006;
      else if(score_r==6)pixel_addr_score2 <= ((pixel_y)-pos_score2_y+25)*51+(pixel_x-pos_score2_x+25)+15607;
      else if(score_r==7)pixel_addr_score2 <= ((pixel_y)-pos_score2_y+25)*51+(pixel_x-pos_score2_x+25)+18208;
  else if(P==S_MAIN_IDLE||P==S_MAIN_DELAY)
    pixel_addr_score2 <=0;
end
 // for show score right

// End of the AGU code.
// ------------------------------------------------------------------------





// ------------------------------------------------------------------------
// Send the video data in the sram to the VGA controller
always @(posedge clk) begin
  if (pixel_tick&&(P==S_MAIN_IDLE||P==S_MAIN_DELAY)) rgb_reg <= rgb_next;
end

always @(*) begin
  if (~video_on&&(P==S_MAIN_IDLE||P==S_MAIN_DELAY))rgb_next <= 12'h000; // Synchronization period, must set RGB values to zero.
  else if(ball_region&&fish_region&&data_out_ball!=12'h0F0&&(P==S_MAIN_IDLE||P==S_MAIN_DELAY))rgb_next<=data_out_ball;
  else if(ball_region&&fish_region1&&data_out_ball!=12'h0F0&&(P==S_MAIN_IDLE||P==S_MAIN_DELAY))rgb_next<=data_out_ball;   
  else if(ball_region&&fish_region&&data_out_left!=12'h0F0&&(P==S_MAIN_IDLE||P==S_MAIN_DELAY))rgb_next<=data_out_left;
  else if(ball_region&&fish_region1&&data_out_right!=12'h0F0&&(P==S_MAIN_IDLE||P==S_MAIN_DELAY))rgb_next<=data_out_right;   
  else if(fish_region&&data_out_left!=12'h0F0&&(P==S_MAIN_IDLE||P==S_MAIN_DELAY))rgb_next<=data_out_left;
  else if(fish_region1&&data_out_right!=12'h0F0&&(P==S_MAIN_IDLE||P==S_MAIN_DELAY))rgb_next<=data_out_right;
  else if(ball_region&&data_out_ball!=12'h0F0&&(P==S_MAIN_IDLE||P==S_MAIN_DELAY))rgb_next<=data_out_ball; 
  else if(score_region&&data_out_score!=12'h0F0)rgb_next<=data_out_score;  
  else if(score_region2&&data_out_score2!=12'h0F0)rgb_next<=data_out_score2; 
  else if(P==S_MAIN_IDLE||P==S_MAIN_DELAY)rgb_next <= data_out;
end
// End of the video data display code.
// ------------------------------------------------------------------------

endmodule
