module block_memory(
	input clock, reset, enable,
	input [4:0] row1, row2, // 0~29
	input [4:0] col1, col2, // 0~9
	input [1:0] func,
	input [1:0] stage,
	output [2:0] block1, block2,
	output busy
);

localparam MAXROW = 30;
localparam READY = 2'b00;
localparam LOAD = 2'b01;
localparam PULL = 2'b10;
localparam DROP = 2'b11;

reg write;
reg [4:0] cnt, addr1;
wire [4:0] addr2;
reg [1:0] state, next_state;
reg [1:0] rom_stage;
wire [29:0] rom_out, out1, out2;
reg [29:0] mem_out, w_data;
wire rom_enable, end_func, m_write;

assign busy = state != READY;
assign block1 = (out1 >> col1*3) & 3'b111;
assign block2 = (out2 >> col2*3) & 3'b111;

// memory control
assign addr2 = row2;
always @(*)
begin
	case (state)
		READY: addr1 = row1;
		LOAD: addr1 = cnt;
		default: begin
			if (write)
				addr1 = cnt;
			else if (state == PULL)
				addr1 = cnt+1;
			else
				addr1 = cnt-1;
		end
	endcase
end
assign m_write = state == READY ? enable && func == 2'b00 : write;
memory mem(clock, m_write, addr1, addr2, w_data, out1, out2);

assign rom_enable = state == LOAD;
stage_rom rom(clock, rom_enable, cnt, rom_stage, rom_out);


// counter
always @(posedge clock)
begin
	if (state == READY) begin
		cnt <= 5'b00000;
	end else if (write) begin
		cnt <= cnt + 1;
	end
end

// state control
always @(posedge clock)
begin
	if (reset) state <= READY;
	else state <= next_state;
end


assign end_func = cnt == MAXROW-1 && write;
always @(*)
begin
	if (end_func)
		next_state = READY;
	else case (state)
		READY: next_state = enable ? func : READY;
		LOAD: next_state = LOAD;
		PULL: next_state = PULL;
		DROP: next_state = DROP;
		default: next_state = 2'bxx;
	endcase
end


// load stage
always @(posedge clock)
begin
	if (reset)
		rom_stage <= 2'b00;
	else if (enable && func == LOAD && ~busy)
		rom_stage <= stage;
end

// pull/drop
always @(posedge clock)
begin
	if (~write)
		case (state)
			PULL: begin
				if (cnt == 5'b11101)
					mem_out <= 30'b000000000000000000000000000000;
				else
					mem_out <= out1;
			end
			DROP: begin
				if (cnt == 5'b00000)
					mem_out <= 30'b000000000000000000000000000000;
				else
					mem_out <= out1;
			end
			default: mem_out <= 30'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
		endcase
	else
		mem_out <= 30'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
end

always @(*)
begin
	if (state == READY)
		w_data = out1 &(30'b111111111111111111111111111111 ^ (3'b111 << col1*3));
	else if (state == LOAD)
		w_data = rom_out;
	else
		w_data = mem_out;
end

always @(posedge clock)
begin
	if (~busy)
		write <= 1'b0;
	else
		write <= ~write;
end

endmodule
