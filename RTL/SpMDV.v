module SpMDV 
(
	input clk,
	input rst,

	// Input signals
	input start_init,
    input [7 : 0] raw_input,
    input raw_data_valid,
	input w_input_valid,

	// Ouput signals
    output reg raw_data_request,
	output reg ld_w_request,
	output reg [21 : 0] o_result,
	output reg o_valid
);
	// state params
		localparam S_IDLE 			= 0;
		localparam S_LOAD_WEIGHT 	= 1;
		localparam S_LOAD_INDEX 	= 2;
		localparam S_LOAD_BIAS 		= 3;
		localparam S_INIT_DONE		= 4;
		localparam S_LOAD_VECTORS	= 5;
		localparam S_LOAD_CUR_VEC	= 6;
		localparam S_LOAD_DONE 		= 7;
		localparam S_OUTPUT			= 8;
		localparam S_VEC_DONE		= 9;
	
	// vars
		integer i;
		genvar g;

	// wire & reg declarations 
		// counter signals
			reg row_counter_en, row_counter_rst;
			wire [7:0] row_counter_out;
			reg col_counter_en, col_counter_rst;
			wire [5:0] col_counter_out;
			reg vector_counter_en, vector_counter_rst;
			wire [3:0] vector_counter_out;
		
		// sram signals
			reg [47:0] weight_sram_cen, weight_sram_wen, index_sram_cen, index_sram_wen;
			reg [7:0] weight_sram_addr[0:47], index_sram_addr[0:47];
			wire signed [7:0] weight_sram_Q[0:47], index_sram_Q[0:47];
			reg [7:0] weight_sram_D[0:47], index_sram_D[0:47];

			reg bias_sram_cen, bias_sram_wen;
			reg [7:0] bias_sram_addr;
			wire signed [7:0] bias_sram_Q;
			reg [7:0] bias_sram_D;

			reg vector_sram_cen, vector_sram_wen;
			reg [11:0] vector_sram_addr;
			wire signed [7:0] vector_sram_Q;
			reg [7:0] vector_sram_D;
		
		// current vector registers
			reg [7:0] vector_reg_addr, vector_reg_addr_nxt;
			reg signed [7:0] vector[0:255], vector_nxt[0:255];

		// intermediate results
			reg signed [15:0] product[0:47], product_nxt[0:47];
			reg signed [21:0] sum[0:48];
			reg signed [7:0] b_reg, b_reg_nxt;
			reg valid_p1, valid_p1_nxt, valid_p2, valid_p2_nxt;
			reg [21:0] result_reg, result_reg_nxt;
			wire signed [7:0] mul_x[0:47], mul_y[0:47];
		
		// FSM
			reg [3:0] state, state_nxt;

	// module instantiation
		COUNTER #(.WIDTH(8)) row_counter (.clk(clk), .rst(row_counter_rst), .en(row_counter_en), .out(row_counter_out));
		COUNTER_6 col_counter (.clk(clk), .rst(col_counter_rst), .en(col_counter_en), .out(col_counter_out));
		COUNTER_4 vector_counter (.clk(clk), .rst(vector_counter_rst), .en(vector_counter_en), .out(vector_counter_out));
		generate
			for (g=0; g<48; g=g+1) begin: gen_sram
				sram_256x8 weight_sram(
					.Q(weight_sram_Q[g]),
					.CLK(clk),
					.CEN(weight_sram_cen[g]),
					.WEN(weight_sram_wen[g]),
					.A(weight_sram_addr[g]),
					.D(weight_sram_D[g])
				);
				sram_256x8 index_sram(
					.Q(index_sram_Q[g]),
					.CLK(clk),
					.CEN(index_sram_cen[g]),
					.WEN(index_sram_wen[g]),
					.A(index_sram_addr[g]),
					.D(index_sram_D[g])	
				);
			end
		endgenerate
		sram_256x8 bias_sram(
			.Q(bias_sram_Q),
			.CLK(clk),
			.CEN(bias_sram_cen),
			.WEN(bias_sram_wen),
			.A(bias_sram_addr),
			.D(bias_sram_D)
		);
		sram_4096x8 vector_sram(
			.Q(vector_sram_Q),
			.CLK(clk),
			.CEN(vector_sram_cen),
			.WEN(vector_sram_wen),
			.A(vector_sram_addr),
			.D(vector_sram_D)	
		);
	
	// combinational
		// weight sram
			always @(*) begin
				case (state) 
					S_LOAD_WEIGHT: begin	
						for (i=0;i<48;i=i+1) begin
							weight_sram_addr[i] = row_counter_out;
							weight_sram_D[i] = raw_input;
							if (i == col_counter_out) begin
								weight_sram_cen[i] = ~w_input_valid;
								weight_sram_wen[i] = ~w_input_valid;
							end
							else begin
								weight_sram_cen[i] = 1'b1;
								weight_sram_wen[i] = 1'b1;
							end
						end
					end
					S_LOAD_DONE: begin
						for (i=0;i<48;i=i+1) begin
							weight_sram_addr[i] = row_counter_out;
							weight_sram_D[i] = 0;
							weight_sram_cen[i] = 1'b0;
							weight_sram_wen[i] = 1'b1;
						end
					end
					S_OUTPUT: begin
						for (i=0;i<48;i=i+1) begin
							weight_sram_addr[i] = row_counter_out;
							weight_sram_D[i] = 0;
							weight_sram_cen[i] = 1'b0;
							weight_sram_wen[i] = 1'b1;
						end
					end
					default: begin
						for (i=0;i<48;i=i+1) begin
							weight_sram_addr[i] = 0;
							weight_sram_D[i] = 0;
							weight_sram_cen[i] = 1'b1;
							weight_sram_wen[i] = 1'b1;
						end
					end
				endcase
			end

		// index sram
			always @(*) begin
				case (state) 
					S_LOAD_INDEX: begin	
						for (i=0;i<48;i=i+1) begin
							index_sram_addr[i] = row_counter_out;
							index_sram_D[i] = raw_input;
							if (i == col_counter_out) begin
								index_sram_cen[i] = ~w_input_valid;
								index_sram_wen[i] = ~w_input_valid;
							end
							else begin
								index_sram_cen[i] = 1'b1;
								index_sram_wen[i] = 1'b1;
							end
						end
					end
					S_LOAD_DONE: begin
						for (i=0;i<48;i=i+1) begin
							index_sram_addr[i] = row_counter_out;
							index_sram_D[i] = 0;
							index_sram_cen[i] = 1'b0;
							index_sram_wen[i] = 1'b1;
						end
					end
					S_OUTPUT: begin
						for (i=0;i<48;i=i+1) begin
							index_sram_addr[i] = row_counter_out;
							index_sram_D[i] = 0;
							index_sram_cen[i] = 1'b0;
							index_sram_wen[i] = 1'b1;
						end
					end
					default: begin
						for (i=0;i<48;i=i+1) begin
							index_sram_addr[i] = 0;
							index_sram_D[i] = 0;
							index_sram_cen[i] = 1'b1;
							index_sram_wen[i] = 1'b1;
						end
					end
				endcase
			end

		// bias sram
			always @(*) begin
				case (state) 
					S_LOAD_BIAS: begin
						bias_sram_cen = 1'b0;
						bias_sram_wen = 1'b0;
						bias_sram_addr = row_counter_out;
						bias_sram_D = raw_input;
					end
					S_LOAD_DONE: begin
						bias_sram_cen = 1'b0;
						bias_sram_wen = 1'b1;
						bias_sram_addr = row_counter_out;
						bias_sram_D = 0;
					end
					S_OUTPUT: begin
						bias_sram_cen = 1'b0;
						bias_sram_wen = 1'b1;
						bias_sram_addr = row_counter_out;
						bias_sram_D = 0;
					end
					default: begin
						bias_sram_cen = 1'b1;
						bias_sram_wen = 1'b1;
						bias_sram_addr = 0;
						bias_sram_D = 0;
					end
				endcase
			end

		// vector sram
			always @(*) begin
				case (state)
					S_LOAD_VECTORS: begin
						vector_sram_cen = 1'b0;
						vector_sram_wen = 1'b0;
						vector_sram_addr = vector_counter_out * 256 + row_counter_out;
						vector_sram_D = raw_input;
					end
					S_LOAD_CUR_VEC: begin
						vector_sram_cen = 1'b0;
						vector_sram_wen = 1'b1;
						vector_sram_addr = vector_counter_out * 256 + row_counter_out;
						vector_sram_D = 0;
					end
					default: begin
						vector_sram_cen = 1'b1;
						vector_sram_wen = 1'b1;
						vector_sram_addr = 0;
						vector_sram_D = 0;
					end
				endcase
			end	

		// vector registers
			always @(*) begin
				vector_reg_addr_nxt = row_counter_out;
				case (state) 
					S_LOAD_CUR_VEC: begin
						for (i=0;i<256;i=i+1) begin
							if (vector_reg_addr == 255) begin
								vector_nxt[i] = vector[i];
							end
							else begin								
								if (i == vector_reg_addr)
									vector_nxt[i] = vector_sram_Q;
								else 
									vector_nxt[i] = vector[i];
							end
						end
					end
					S_LOAD_DONE: begin
						for (i=0;i<256;i=i+1) begin							
							if (i == vector_reg_addr)
								vector_nxt[i] = vector_sram_Q;
							else 
								vector_nxt[i] = vector[i];
						end
					end
					default: begin
						for (i=0;i<256;i=i+1) begin
							vector_nxt[i] = vector[i];
						end
					end
				endcase 	
			end

		// counter signals 
			always @(*) begin 
				case (state)
					S_LOAD_WEIGHT, S_LOAD_INDEX: begin
						row_counter_en = col_counter_out == 47;
					end
					S_LOAD_BIAS, S_LOAD_VECTORS, S_LOAD_CUR_VEC, S_LOAD_DONE, S_OUTPUT: begin
						row_counter_en = 1'b1;
					end
					default:
						row_counter_en = 1'b0;
				endcase
				row_counter_rst = rst;

				case (state)
					S_LOAD_WEIGHT, S_LOAD_INDEX: begin
						col_counter_en = w_input_valid;
					end
					default:
						col_counter_en = 1'b0;
				endcase
				col_counter_rst = rst | col_counter_out == 47;

				case (state)
					S_LOAD_VECTORS, S_OUTPUT: begin
						vector_counter_en = row_counter_out == 255;
					end
					default:
						vector_counter_en = 1'b0;
				endcase
				vector_counter_rst = rst;
			end

		// next state logic
			always @(*) begin
				case (state) // synopsys full_case
					S_IDLE:			state_nxt = start_init ? S_LOAD_WEIGHT : S_IDLE;
					S_LOAD_WEIGHT:	state_nxt = ((row_counter_out == 255) && (col_counter_out == 47)) ? S_LOAD_INDEX : S_LOAD_WEIGHT;
					S_LOAD_INDEX:	state_nxt = ((row_counter_out == 255) && (col_counter_out == 47)) ? S_LOAD_BIAS : S_LOAD_INDEX;
					S_LOAD_BIAS:	state_nxt = (row_counter_out == 255) ? S_INIT_DONE : S_LOAD_BIAS;
					S_INIT_DONE:	state_nxt = S_LOAD_VECTORS;
					S_LOAD_VECTORS:	state_nxt = ((row_counter_out == 255) && (vector_counter_out == 15)) ? S_LOAD_CUR_VEC : S_LOAD_VECTORS;
					S_LOAD_CUR_VEC:	state_nxt = (row_counter_out == 255) ? S_LOAD_DONE : S_LOAD_CUR_VEC;
					S_LOAD_DONE:	state_nxt = S_OUTPUT;
					S_OUTPUT:		state_nxt = (row_counter_out != 255) ? S_OUTPUT : S_VEC_DONE;
					S_VEC_DONE:		state_nxt = (vector_counter_out == 0) ? S_INIT_DONE : S_LOAD_CUR_VEC;
				endcase
			end

		// request signals
			always @(*) begin
				raw_data_request = state == S_INIT_DONE || (state == S_LOAD_VECTORS && !((row_counter_out == 255) && (vector_counter_out == 15)));
				ld_w_request = (state == S_IDLE && start_init) | (state == S_LOAD_WEIGHT) | (state == S_LOAD_INDEX) | (state == S_LOAD_BIAS);
			end
		
		// output
			generate 
				for (g=0;g<48;g=g+1) begin: gen_mul
					assign mul_x[g] = (state == S_OUTPUT || state == S_VEC_DONE) ? vector[index_sram_Q[g]+64*g[1:0]] : 0;
					assign mul_y[g] = (state == S_OUTPUT || state == S_VEC_DONE) ? weight_sram_Q[g] : 0;
				end
			endgenerate
			always @(*) begin
				for (i=0;i<48;i=i+1) begin
					product_nxt[i] = mul_x[i] * mul_y[i];
				end
				// TODO
				sum[0] = $signed({b_reg, 4'b0});
				for (i=1;i<49;i=i+1) begin
					sum [i] = sum[i-1] + product[i-1];
				end
				b_reg_nxt = bias_sram_Q;
				result_reg_nxt = sum[48];
				valid_p1_nxt = state == S_OUTPUT || state == S_VEC_DONE;
				valid_p2_nxt = valid_p1;
				o_valid = valid_p2;
				o_result = result_reg;
			end


	// sequential
		// FF with reset
			always @(posedge clk or posedge rst) begin
				if (rst) begin
					state <= S_IDLE;
				end
				else begin
					state <= state_nxt;
				end
			end

		// FF without reset 
			always @(posedge clk) begin
				for (i=0;i<256;i=i+1) begin
					vector[i] <= vector_nxt[i];
				end
				for (i=0;i<48;i=i+1) begin
					product[i] <= product_nxt[i];
				end
				vector_reg_addr <= vector_reg_addr_nxt;
				b_reg <= b_reg_nxt;
				result_reg <= result_reg_nxt;
				valid_p1 <= valid_p1_nxt;
				valid_p2 <= valid_p2_nxt;
			end

endmodule

module COUNTER #(parameter WIDTH = 8) (
	input clk,
	input rst,
	input en,
	output [WIDTH-1:0] out
);
	// wire & reg
		reg [WIDTH-1:0] counter, counter_nxt;
	
	// combinational 
		always @(*) begin
			counter_nxt = en ? counter + 1 : counter;
		end
		assign out = counter;

	// sequential 
		always @(posedge clk) begin
			if (rst)
				counter <= 0;
			else 
				counter <= counter_nxt;
		end
endmodule

module COUNTER_6 (
	input clk,
	input rst,
	input en,
	output [5:0] out
);
	// wire & reg
		reg [5:0] counter, counter_nxt;
	
	// combinational 
		always @(*) begin
			counter_nxt = en ? counter + 1 : counter;
		end
		assign out = counter;

	// sequential 
		always @(posedge clk) begin
			if (rst)
				counter <= 0;
			else 
				counter <= counter_nxt;
		end
endmodule

module COUNTER_4 (
	input clk,
	input rst,
	input en,
	output [3:0] out
);
	// wire & reg
		reg [3:0] counter, counter_nxt;
	
	// combinational 
		always @(*) begin
			counter_nxt = en ? counter + 1 : counter;
		end
		assign out = counter;

	// sequential 
		always @(posedge clk) begin
			if (rst)
				counter <= 0;
			else 
				counter <= counter_nxt;
		end
endmodule
