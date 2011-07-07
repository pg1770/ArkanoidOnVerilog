module state_control
#(
	parameter BALL_NUM = 2,
	parameter SHOT_NUM = 2
)
(
	input clock, reset, start, btn_l, btn_r,
	input [3:0] iSW,
	input bm_ready,
	input [3:0] bm_block,
	input [9:0] p_x, p_y,
	output [5:0] p_radius, b_radius,
	output [BALL_NUM*10-1:0] o_bx, o_by,
	output reg [BALL_NUM-1:0] b_active,
	output reg [SHOT_NUM*2-1:0] o_sx, o_sy,
	output [SHOT_NUM-1:0] s_active,
	output reg bm_enable,
	output [4:0] bm_row, bm_col,
	output reg [1:0] bm_func,
	output [1:0] bm_stage,
	output dead, init
);

`include "def.v"

localparam UNIT = 2000000;
localparam ST_INIT = 2'b00;
localparam ST_WAIT = 2'b01;
localparam ST_PLAY = 2'b10;
localparam ST_DEAD = 2'b11;

assign b_radius = 8;
assign p_radius = 16;





wire bm_empty;
wire load_stage;

wire [5:0] bl_radius;
reg [1:0] state, next_state;
reg [9:0] b_x[BALL_NUM-1:0], b_y[BALL_NUM-1:0];
wire [9:0] bl_x, bl_y;
reg [9:0] b_ang_x[BALL_NUM-1:0], b_ang_y[BALL_NUM-1:0];
reg b_di_x[BALL_NUM-1:0], b_di_y[BALL_NUM-1:0];
wire [40:0] b_cntx[BALL_NUM-1:0], b_cnty[BALL_NUM-1:0];
wire [BALL_NUM-1:0] b_rstx, b_rsty;
wire [BALL_NUM-1:0] b_bounced_p, b_bounced_bl, b_bounced;
wire [1:0] b_bdi_p[BALL_NUM-1:0], b_bdi_bl[BALL_NUM-1:0], b_bdi[BALL_NUM-1:0];
reg [1:0] stage, next_stage;

wire bl_enable, bl_rstc, bl_rstr;
assign bl_x = LEFT + 16 + bm_col*32;
assign bl_y = TOP + 8 + bm_row*16;
assign bm_stage = next_stage;
assign load_stage = (state == ST_INIT || state == ST_PLAY) && next_state == ST_WAIT;

always @(posedge clock)
begin
	if (reset)
		b_active <= 0;
	else if (next_state == ST_WAIT)
		b_active[0] <= 1'b1;
end

always @(*)
begin
	bm_enable = 1'b0;
	bm_func = 2'bxx;
	if ((state == ST_INIT && start ) || (state == ST_PLAY && next_state == ST_WAIT)) begin
		bm_enable = 1'b1;
		bm_func = F_LOAD;
	end else if (state == ST_PLAY && b_bounced_bl) begin
		bm_enable = 1'b1;
		bm_func = F_CLEAR;
	end else if (btn_r) begin
		bm_enable = 1'b1;
		bm_func = 2'b11;
	end else if (btn_l) begin
		bm_enable = 1'b1;
		bm_func = 2'b10;
	end
end

generate
genvar i;
for (i=0; i<BALL_NUM; i=i+1) begin : b_genblock
	counter #(40) cntx(clock, b_rstx[i], 1'b1, b_cntx[i]);
	counter #(40) cnty(clock, b_rsty[i], 1'b1, b_cnty[i]);
	bounce_detect p_bounce(1'b1, b_x[i], b_y[i], b_radius, p_x, p_y, p_radius, PD_H, b_bounced_p[i], b_bdi_p[i]);
	bounce_detect bl_bounce(bm_block != 0 && bm_ready, b_x[i], b_y[i], b_radius, bl_x, bl_y, bl_radius, 8, b_bounced_bl[i], b_bdi_bl[i]);

	assign o_bx[i*10+9:i*10] = b_x[i];
	assign o_by[i*10+9:i*10] = b_y[i];
	assign b_rstx[i] = reset || (b_cntx[i]*b_ang_x[i] >= UNIT);
	assign b_rsty[i] = reset || (b_cnty[i]*b_ang_y[i] >= UNIT);
	assign b_bounced[i] = b_bounced_p[i] | b_bounced_bl[i];
	assign b_bdi[i] = b_bounced_bl[i] ? b_bdi_bl[i] : b_bdi_p[i];
end
endgenerate

always @(posedge clock)
begin
	if (reset)
		state <= ST_INIT;
	else
		state <= next_state;
end

always @(*)
begin
	case (state)
		ST_INIT: begin
			if (start && bm_ready)
				next_state = ST_WAIT;
			else
				next_state = ST_INIT;
		end
		ST_WAIT: begin
			if (start && bm_ready)
				next_state = ST_PLAY;
			else
				next_state = ST_WAIT;
		end
		ST_PLAY: begin
			if (0'b0 /*&& ball_num*/)
				next_state = ST_DEAD;
			else if (bm_empty)
				next_state = stage == 2'b11 ? ST_INIT : ST_WAIT;
			else
				next_state = ST_PLAY;
		end
		ST_DEAD: next_state = ST_DEAD;
		default:
			next_state = 2'bxx;
	endcase
end


/*
always @(*)
begin
	case (state)
		ST_INIT: begin
			if (start);
			else;
	endcase
end
*/

// stage control
always @(posedge clock)
begin
	if (reset)
		stage <= 2'b00;
	else if (load_stage)
		stage <= next_stage;
end
always @(*)
begin
	if (iSW[1:0] == 2'b11)
		next_stage = iSW[3:2];
	else if (state == ST_INIT)
		next_stage = 2'b00;
	else
		next_stage = (stage + 1)%4;
end

// block counter
assign bl_enable = bm_col >= 4'd9;
assign bl_rstc = reset || bl_enable;
assign bl_rstr = reset || (bm_row >= 5'd29 && bl_enable);
counter #(5) cntblc(clock, bl_rstc, 1'b1, bm_col);
counter #(5) cntblr(clock, bl_rstr, bl_enable, bm_row);

reg scan_empty;
always @(posedge clock)
begin
	if (reset || ~bm_ready || bm_enable || bm_block)
		scan_empty <= 1'b0;
	else if (bm_row == 0 && bm_col == 0)
		scan_empty <= 1'b1;
end

assign bm_empty = (reset || ~bm_ready || bm_block) ? 1'b0 : bm_row == 5'd29 && scan_empty;

assign bl_radius = bm_block[2] ? 16 : 8;




// Ball control

// Speed control counters.



// Ball Moving
always @(posedge clock)
begin : bmove_block
	integer i;
	for (i=0; i<2; i=i+1) begin
		if (reset) begin
			b_x[i] <= LEFT+MAXX/2;
			b_y[i] <= TOP+MAXY/2;
		end else case (state)
			ST_PLAY: begin
				if (b_cntx[i]*b_ang_x[i] >= UNIT) begin
					if (b_di_x[i])
						b_x[i] <= b_x[i]-1;
					else
						b_x[i] <= b_x[i]+1;
				end

				if (b_cnty[i]*b_ang_y[i] >= UNIT) begin
					if (b_di_y[i])
						b_y[i] <= b_y[i]-1;
					else
						b_y[i] <= b_y[i]+1;
				end
			end
			ST_WAIT: begin
				b_x[i] <= p_x;
				b_y[i] <= p_y - b_radius - PD_H;
			end
			default: begin
				b_x[i] <= 10'bxxxxxxxxxx;
				b_y[i] <= 10'bxxxxxxxxxx;
			end
		endcase
	end
end


// Ball bouncing
always @(posedge clock)
begin
	if (reset) begin
		b_ang_x[0] = 5;
		b_ang_y[0] = 5;
		b_ang_x[1] = 10;
		b_ang_y[1] = 2;
	end else begin : bounce_block
		integer i;
		for (i=0; i<2; i=i+1) begin
			if (LEFT + b_radius >= b_x[i] || (b_bounced[i] && b_bdi[i] == B_RIGHT)) begin
				// bounce left side
				b_di_x[i] = 1'b0;
			end else if (b_x[i] + b_radius >= LEFT+MAXX || (b_bounced[i] && b_bdi[i] == B_LEFT)) begin
				// bounce right side
				b_di_x[i] = 1'b1;
			end
			if (TOP + b_radius > b_y[i] || (b_bounced[i] && b_bdi[i] == B_DOWN)) begin
				// bounce top side
				b_di_y[i] = 1'b0;
			end else if (b_y[i] + b_radius >= TOP+MAXY  || (b_bounced[i] && b_bdi[i] == B_UP)) begin
				// bounce down side
				b_di_y[i] = 1'b1;
			end
		end
	end
end

endmodule
