//
// RVOOM! Risc-V superscalar O-O
// Copyright (C) 2019-21 Paul Campbell - paul@taniwha.com
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
// 


//
//	ALU - 'B' is defined for the B (bitfield) extension
//

`ifdef B
module alu_ffs4(input [3:0]in, output [1:0]out, output zero);
	reg z;
	reg [1:0]o;
	assign zero = z;
	assign out = o;
	always @(*) begin
		z = 0;
		o = 2'bxx;
		casez (in) // synthesis fullcase parallel_case
		4'b0000: z=1;
		4'b0001: o=3;
		4'b001?: o=2;
		4'b01??: o=1;
		4'b1???: o=0;

		endcase
	end
endmodule
module alu_ffr4(input [3:0]in, output [1:0]out);
	reg [1:0]o;
	assign out = o;
	always @(*) begin
		o = 2'bxx;
		casez (in) // synthesis fullcase parallel_case
		4'b1000: o=3;
		4'b?100: o=2;
		4'b??10: o=1;
		4'b???1: o=0;
		endcase
	end
endmodule

module alu_pop_count4(input [3:0]in, output [2:0]out);
	reg [1:0]o;
	assign out = o;
	always @(*) begin
		o = 3'bxx;
		casez (in) // synthesis fullcase parallel_case
		4'b0000: o=0;
		4'b1000,
		4'b0100,
		4'b0010,
		4'b0001: o=1;
		4'b1001,
		4'b1010,
		4'b1100,
		4'b0101,
		4'b0110,
		4'b0011: o=2;
		4'b1110,
		4'b1101,
		4'b1011,
		4'b0111: o=3;
		4'b1111: o=4;
		endcase
	end
endmodule

module alu_pop_count32(input [31:0]in, output [5:0]out);

	wire [2:0]out0, out1, out2, out3;
	wire [2:0]out4, out5, out6, out7;

	alu_pop_count4 p0(.in(in[3:0]), .out(out0));
	alu_pop_count4 p1(.in(in[7:4]), .out(out1));
	alu_pop_count4 p2(.in(in[11:8]), .out(out2));
	alu_pop_count4 p3(.in(in[15:12]), .out(out3));
	alu_pop_count4 p4(.in(in[19:16]), .out(out4));
	alu_pop_count4 p5(.in(in[23:20]), .out(out5));
	alu_pop_count4 p6(.in(in[27:24]), .out(out6));
	alu_pop_count4 p7(.in(in[31:28]), .out(out7));

	assign out = {2'b0, out0} +
				 {2'b0, out1} +
				 {2'b0, out2} +
				 {2'b0, out3} +
				 {2'b0, out4} +
				 {2'b0, out5} +
				 {2'b0, out6} +
				 {2'b0, out7};
endmodule
`endif

module alu(
	input clk,
	input reset, 
	input enable,
`ifdef SIMD
	input simd_enable,
`endif

	input [CNTRL_SIZE-1:0]control,
	input     [LNCOMMIT-1:0]rd,
	input	          makes_rd,
	input 		  needs_rs2,
	input [RV-1:0]r1, r2,
	input [RV-1:1]pc,
	input [31:0]immed,
	input	[(NHART==1?0:LNHART-1):0]hart,
	input	rv32,

	output [RV-1:0]result,
	output [LNCOMMIT-1:0]res_rd, 
	output [NHART-1:0]res_makes_rd 
	);

    parameter CNTRL_SIZE=7;
    parameter ADDR=0;
    parameter NHART=1;
 	parameter RV=64;
    parameter LNHART=0;
    parameter NCOMMIT = 32; // number of commit registers
    parameter LNCOMMIT = 5; // number of bits to encode that
 	parameter RA=5;

	//
	//	ctrl:
	//	5 - rs1 input is pc - op != 6/7
	//	4 - addw
	//	3 - inv rs2 (plus carry in)
	//	5,2:0 - op 0 - add r1 << 0
	//			   1 - xor
	//			   2 - and
	//			   3 - or
	//			   4 - slt
	//			   5 - sltu
	//			   6 - min/minu
	//			   7 - max/maxu
	//			   8 - add r1 = pc
	//			   9 - add r1 << 1
	//			   a - add r1 << 2
	//			   b - add r1 << 2
	//			   c - add r1 << 0 sign extend .w with 0
	//			   d - clz/pcnt/etc

	reg [RV-1:0]r_res, c_res;
	assign result = r_res;
	reg  [LNCOMMIT-1:0]r_res_rd, r_rd;
	assign res_rd = r_res_rd;
	reg  [NHART-1:0]r_res_makes_rd;
	assign res_makes_rd = r_res_makes_rd;
	wire [ 3:0]op;
	wire	inv, unsign;
	wire	addw;
	wire	in_pc;
	reg [ 3:0]r_op;
	reg	r_inv, r_unsigned;
	reg	r_addw;
	reg	r_in_pc;
	reg	r_makes_rd;
	reg	r_needs_rs2;
	reg r_rv32;
	assign addw = control[4];
	assign op = {control[5],control[2:0]};
	assign inv = control[3]||(op == 4'h7 || op == 4'h6);
	assign unsign = control[3];

	reg	[RV-1:0]r_immed;
	reg	[RV-1:1]r_pc;
	always @(posedge clk) begin
		r_unsigned <= unsign;
		r_pc <= pc;
		r_needs_rs2 <= needs_rs2;
		r_immed <= {{32{immed[31]}},immed};
		r_makes_rd <= makes_rd&enable;
		r_op <= op;
		r_inv <= inv;
		r_addw <= addw;
		r_rd <= rd;
		r_rv32 <= rv32;
		r_res_rd <= r_rd;
		r_res <= c_res;
`ifdef SIMD
		if (r_makes_rd && simd_enable) $display("A %d %x @ %x <- %x",$time,{r_pc, 1'b0},r_rd,c_res);
`endif
	end

	generate
		if (NHART == 1) begin
			always @(posedge clk) 
				r_res_makes_rd <= r_makes_rd;
		end else begin
			always @(posedge clk) 
				r_res_makes_rd <= (r_makes_rd?1<<hart:0);
		end
	endgenerate

	wire [RV-1:0]x_r2 = r_needs_rs2?r2:r_immed;
	reg [RV-1:0]c_r1;
	always @(*) begin
		casez ({r_addw, r_op}) // synthesis full_case parallel_case
		5'b?_1000: c_r1 = {r_pc,1'b0};
		5'b0_1001: c_r1 = {r1[62:0], 1'b0};
		5'b0_1010: c_r1 = {r1[61:0], 2'b0};
		5'b0_1011: c_r1 = {r1[60:0], 3'b0};
		5'b1_1001: c_r1 = {31'b0, r1[31:0], 1'b0};
		5'b1_1010: c_r1 = {30'b0, r1[31:0], 2'b0};
		5'b1_1011: c_r1 = {29'b0, r1[31:0], 3'b0};
		default: c_r1 = r1;
		endcase
	end
	wire [RV-1:0]c_r2 = (r_inv?~x_r2:x_r2);							// inverter
	wire [RV:0]c_add64 = {1'b0,c_r1}+{1'b0,c_r2}+{64'b0,r_inv};		// main adder (+carry if r_inv)
	wire [RV-1:0]c_add = (RV==64&&r_addw?{(r_op==12?32'b0:{32{c_add64[31]}}), c_add64[31:0]}: c_add64); // addw stuff

	wire s_lt = (RV==64 ? c_add64[63]^((c_add64[63]&~c_r1[63]&~c_r2[63])|(~c_add64[64]&c_r1[63]&c_r2[63])) :
			              c_add64[31]^((c_add64[31]&~c_r1[31]&~c_r2[31])|(~c_add64[32]&c_r1[31]&c_r2[31])));
	wire u_lt = (RV==64 ? ~c_add64[64] : ~c_add64[32]);

`ifdef B
	reg [5:0]pc0, pc1;
	wire [6:0]pcx = {1'b0, pc0}+{1'b0, pc1};
	reg [6:0]fclz, fctz;
`endif


	always @(*) begin
		c_res = 'bx;
		case (r_op) // synthesis full_case parallel_case
		0,8,9,10,11,12: c_res = c_add[RV-1:0];						// add
		1: c_res = c_r1^c_r2;										// xor
		2: c_res = c_r1&c_r2;										// and
		3: c_res = c_r1|c_r2;										// or
		4: c_res = (RV==64 ?  {63'b0, s_lt} : {31'b0, s_lt});		// lt
		5: c_res = (RV==64 ?  {63'b0, u_lt} : {31'b0, u_lt});		// ltu
`ifdef B
		6: c_res = ((r_unsigned?u_lt:s_lt)?c_r1:c_r2);				// min
		7: c_res = ((r_unsigned?u_lt:s_lt)?c_r1:c_r2);				// max
		13:	casez ({r_addw|r_rv32, r_immed[1:0]}) // synthesis full_case parallel_case
			3'b?_00:												// clz
					c_res = {57'b0, fclz};
			3'b?_01:												// ctz
					c_res = {57'b0, fctz};
			3'b0_10:												// pcnt
				c_res = {57'b0, pcx};
			3'b1_10:												// pcntw
				c_res = {58'b0, pc0};
			endcase
`endif
		endcase
	end

`ifdef B
	alu_pop_count32 p0(.in(r1[31:0]), .out(pc0));	// pop counts
	alu_pop_count32 p1(.in(r1[63:32]), .out(pc1));
	
	wire [15:0]ffz;
	wire [1:0]ffs[0:15];
	wire [1:0]ffr[0:15];
	genvar I;
	generate
		for (I = 0; I < 16; I=I+1) begin
			alu_ffs4 fs(.in(r1[4*I+3:4*I]), .zero(ffz[I]), .out(ffs[I]));
			alu_ffr4 fr(.in(r1[4*I+3:4*I]), .out(ffr[I]));
		end
	endgenerate

	always @(*) begin : clz
		reg fxz;
		reg [5:0]fres_hi, fres_lo;

		fxz = 0;
		casez(ffz[15:8]) // synthesis full_case parallel_case
		8'b0???_????:	fres_hi = ffs[15];
		8'b10??_????:	fres_hi = 4|ffs[14];
		8'b110?_????:	fres_hi = 8|ffs[13];
		8'b1110_????:	fres_hi = 12|ffs[12];
		8'b1111_0???:	fres_hi = 16|ffs[11];
		8'b1111_10??:	fres_hi = 20|ffs[10];
		8'b1111_110?:	fres_hi = 24|ffs[9];
		8'b1111_1110:	fres_hi = 28|ffs[8];
		8'b1111_1111:	begin fres_hi = 32; fxz = 1; end
		endcase
		casez(ffz[7:0]) // synthesis full_case parallel_case
		8'b0???_????:	fres_lo = ffs[7];
		8'b10??_????:	fres_lo = 4|ffs[6];
		8'b110?_????:	fres_lo = 8|ffs[5];
		8'b1110_????:	fres_lo = 12|ffs[4];
		8'b1111_0???:	fres_lo = 16|ffs[3];
		8'b1111_10??:	fres_lo = 20|ffs[2];
		8'b1111_110?:	fres_lo = 24|ffs[1];
		8'b1111_1110:	fres_lo = 28|ffs[0];
		8'b1111_1111:	fres_lo = 32; 
		endcase
		casez ({fxz, r_addw|r_rv32}) // synthesis full_case parallel_case; 
		2'b?1: fclz = {1'b0, fres_lo};
		2'b10: fclz = {1'b0, fres_lo}+6'b01_0000;
		2'b00: fclz = {1'b0, fres_hi};
		endcase
	end

	always @(*) begin : ctz
		reg fxz;
		reg [5:0]fres_hi, fres_lo;

		fxz = 0;
		casez(ffz[15:8]) // synthesis full_case parallel_case
		8'b????_???0:	fres_hi = ffr[15];
		8'b????_??01:	fres_hi = 4|ffr[14];
		8'b????_?011:	fres_hi = 8|ffr[13];
		8'b????_0111:	fres_hi = 12|ffr[12];
		8'b???0_1111:	fres_hi = 16|ffr[11];
		8'b??01_1111:	fres_hi = 20|ffr[10];
		8'b?011_1111:	fres_hi = 24|ffr[9];
		8'b0111_1111:	fres_hi = 28|ffr[8];
		8'b1111_1111:	fres_hi = 32; 
		endcase
		casez(ffz[7:0]) // synthesis full_case parallel_case
		8'b????_???0:	fres_lo = ffr[7];
		8'b????_??01:	fres_lo = 4|ffr[6];
		8'b????_?011:	fres_lo = 8|ffr[5];
		8'b????_0111:	fres_lo = 12|ffr[4];
		8'b???0_1111:	fres_lo = 16|ffr[3];
		8'b??01_1111:	fres_lo = 20|ffr[2];
		8'b?011_1111:	fres_lo = 24|ffr[1];
		8'b0111_1111:	fres_lo = 28|ffr[0];
		8'b1111_1111:	begin fres_lo = 32;  fxz = 1; end
		endcase
		casez ({fxz, r_addw|r_rv32}) // synthesis full_case parallel_case; 
		2'b?1: fctz = {1'b0, fres_lo};
		2'b10: fctz = {1'b0, fres_hi}+6'b01_0000;
		2'b00: fctz = {1'b0, fres_lo};
		endcase
	end
`endif
endmodule

/* For Emacs:
 * Local Variables:
 * mode:c
 * indent-tabs-mode:t
 * tab-width:4
 * c-basic-offset:4
 * End:
 * For VIM:
 * vim:set softtabstop=4 shiftwidth=4 tabstop=4:
 */

