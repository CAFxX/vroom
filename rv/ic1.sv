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

module icache_l1(
    input clk,
    input reset,

    input [NPHYS-1:4]raddr0,	// CPU read port
    output rhit0,
    output [127:0]rdata0,

    input [NPHYS-1:4]raddr1,	// CPU read port
    output rhit1,
    output [127:0]rdata1,

	input [NPHYS-1:ACACHE_LINE_SIZE]ic_snoop_addr,			// snoop port
	input 	    ic_snoop_addr_req,
	output 	    ic_snoop_addr_ack,
	input  [1:0]ic_snoop_snoop,

	input		ic_rdata_req,
	input [CACHE_LINE_SIZE-1:0]ic_rdata,
	input [NPHYS-1:ACACHE_LINE_SIZE]ic_raddr,
	input [2:0]ic_rdata_resp,

	input		irand,
	output		orand,

	input dummy);

`include "cache_protocol.si"

	parameter RV=64;
	parameter ACACHE_LINE_SIZE=6;
	parameter CACHE_LINE_SIZE=64*8;		// 64 bytes   5:0	- 6 bits	32 bytes
	parameter NENTRIES=64;				// index      11:6	- 6 bits	4kbytes
`ifdef PSYNTH
	parameter NSETS=16;					//					32k
`else
	parameter NSETS=32;					//					64k
`endif
	parameter NPHYS=56;
	parameter READPORTS=2;
	parameter LFWRITEPORTS=1;
	parameter TRANS_ID_SIZE=6;

	reg   [NENTRIES-1:0]r_valid[0:NSETS-1];

	wire [NPHYS-1:4]raddr[0:READPORTS-1];
	assign raddr[0]=raddr0;
	assign raddr[1]=raddr1;

	wire [READPORTS-1:0]rhit;
	assign rhit0 = rhit[0];
	assign rhit1 = rhit[1];

	wire [CACHE_LINE_SIZE-1:0]rd[0:READPORTS-1][0:NSETS-1];
	reg [CACHE_LINE_SIZE-1:0]rdd[0:READPORTS-1];

	reg [127:0]rdata[0:READPORTS-1];
	assign rdata0 = rdata[0];
	assign rdata1 = rdata[1];

	assign ic_snoop_addr_ack = 1;

	genvar S, R, W, B, M;
	generate
		wire [NSETS-1:0]match_snoop;
		wire [NSETS-1:0]match_dirty;
		wire [NSETS-1:0]match_exclusive;
		wire [NSETS-1:0]match_owned;
		wire [NSETS-1:0]current_valid;
		reg [NSETS-1:0]s;
		

		wire [NSETS-1:0]rdline_valid;
		wire [NSETS-1:0]match_rdline;
		reg  [$clog2(NSETS)-1:0]r_next_evict, c_next_evict;
		reg  [$clog2(NSETS)-1:0]r_rand;
		assign orand = r_rand[$clog2(NSETS)-1];
		always @(posedge clk) 
		if (reset) begin
			r_rand <= 0;
		end else begin
			r_rand <= {r_rand[$clog2(NSETS)-2:0],irand^r_rand[4]^r_rand[2]};
		end
		wire [$clog2(NSETS)-1:0]next_evict = r_next_evict^r_rand;

		reg incoming_valid;
		reg [NSETS-1:0]wl;

		if (NSETS == 16) begin
			always @(*) begin
				wl = 0;
				c_next_evict = r_next_evict;
				incoming_valid = 1;
				if (ic_rdata_req && ic_rdata_resp[0]) begin
					casez (match_rdline&rdline_valid) // synthesis full_case parallel_case
					16'b1???_????_????_????:	wl[15] = 1;
					16'b?1??_????_????_????:	wl[14] = 1;
					16'b??1?_????_????_????:	wl[13] = 1;
					16'b???1_????_????_????:	wl[12] = 1;
					16'b????_1???_????_????:	wl[11] = 1;
					16'b????_?1??_????_????:	wl[10] = 1;
					16'b????_??1?_????_????:	wl[9] = 1;
					16'b????_???1_????_????:	wl[8] = 1;
					16'b????_????_1???_????:	wl[7] = 1;
					16'b????_????_?1??_????:	wl[6] = 1;
					16'b????_????_??1?_????:	wl[5] = 1;
					16'b????_????_???1_????:	wl[4] = 1;
					16'b????_????_????_1???:	wl[3] = 1;
					16'b????_????_????_?1??:	wl[2] = 1;
					16'b????_????_????_??1?:	wl[1] = 1;
					16'b????_????_????_???1:	wl[0] = 1;
					16'b0000_0000_0000_0000: 
						begin
							casez (~rdline_valid) // synthesis full_case parallel_case
							16'b1000_0000_0000_0000:	wl[15] = 1;
							16'b?100_0000_0000_0000:	wl[14] = 1;
							16'b??10_0000_0000_0000:	wl[13] = 1;
							16'b???1_0000_0000_0000:	wl[12] = 1;
							16'b????_1000_0000_0000:	wl[11] = 1;
							16'b????_?100_0000_0000:	wl[10] = 1;
							16'b????_??10_0000_0000:	wl[9] = 1;
							16'b????_???1_0000_0000:	wl[8] = 1;
							16'b????_????_1000_0000:	wl[7] = 1;
							16'b????_????_?100_0000:	wl[6] = 1;
							16'b????_????_??10_0000:	wl[5] = 1;
							16'b????_????_???1_0000:	wl[4] = 1;
							16'b????_????_????_1000:	wl[3] = 1;
							16'b????_????_????_?100:	wl[2] = 1;
							16'b????_????_????_??10:	wl[1] = 1;
							16'b????_????_????_???1:	wl[0] = 1;
							16'b0000_0000_0000_0000:		// have to evict
								begin
									wl[next_evict] = 1;
									c_next_evict = r_next_evict+1;
								end
							endcase
						end
					endcase
				end
			end
		end else begin
			always @(*) begin
				wl = 0;
				c_next_evict = r_next_evict;
				incoming_valid = 1;
				if (ic_rdata_req && ic_rdata_resp[0]) begin
					casez (match_rdline&rdline_valid) // synthesis full_case parallel_case
					32'b1???_????_????_????_????_????_????_????:	wl[31] = 1;
					32'b?1??_????_????_????_????_????_????_????:	wl[30] = 1;
					32'b??1?_????_????_????_????_????_????_????:	wl[29] = 1;
					32'b???1_????_????_????_????_????_????_????:	wl[28] = 1;
					32'b????_1???_????_????_????_????_????_????:	wl[27] = 1;
					32'b????_?1??_????_????_????_????_????_????:	wl[26] = 1;
					32'b????_??1?_????_????_????_????_????_????:	wl[25] = 1;
					32'b????_???1_????_????_????_????_????_????:	wl[24] = 1;
					32'b????_????_1???_????_????_????_????_????:	wl[23] = 1;
					32'b????_????_?1??_????_????_????_????_????:	wl[22] = 1;
					32'b????_????_??1?_????_????_????_????_????:	wl[21] = 1;
					32'b????_????_???1_????_????_????_????_????:	wl[20] = 1;
					32'b????_????_????_1???_????_????_????_????:	wl[19] = 1;
					32'b????_????_????_?1??_????_????_????_????:	wl[18] = 1;
					32'b????_????_????_??1?_????_????_????_????:	wl[17] = 1;
					32'b????_????_????_???1_????_????_????_????:	wl[16] = 1;
					32'b????_????_????_????_1???_????_????_????:	wl[15] = 1;
					32'b????_????_????_????_?1??_????_????_????:	wl[14] = 1;
					32'b????_????_????_????_??1?_????_????_????:	wl[13] = 1;
					32'b????_????_????_????_???1_????_????_????:	wl[12] = 1;
					32'b????_????_????_????_????_1???_????_????:	wl[11] = 1;
					32'b????_????_????_????_????_?1??_????_????:	wl[10] = 1;
					32'b????_????_????_????_????_??1?_????_????:	wl[9] = 1;
					32'b????_????_????_????_????_???1_????_????:	wl[8] = 1;
					32'b????_????_????_????_????_????_1???_????:	wl[7] = 1;
					32'b????_????_????_????_????_????_?1??_????:	wl[6] = 1;
					32'b????_????_????_????_????_????_??1?_????:	wl[5] = 1;
					32'b????_????_????_????_????_????_???1_????:	wl[4] = 1;
					32'b????_????_????_????_????_????_????_1???:	wl[3] = 1;
					32'b????_????_????_????_????_????_????_?1??:	wl[2] = 1;
					32'b????_????_????_????_????_????_????_??1?:	wl[1] = 1;
					32'b????_????_????_????_????_????_????_???1:	wl[0] = 1;
					32'b0000_0000_0000_0000_0000_0000_0000_0000: 
						begin
							casez (~rdline_valid) // synthesis full_case parallel_case
							32'b1000_0000_0000_0000_0000_0000_0000_0000:	wl[31] = 1;
							32'b?100_0000_0000_0000_0000_0000_0000_0000:	wl[30] = 1;
							32'b??10_0000_0000_0000_0000_0000_0000_0000:	wl[29] = 1;
							32'b???1_0000_0000_0000_0000_0000_0000_0000:	wl[28] = 1;
							32'b????_1000_0000_0000_0000_0000_0000_0000:	wl[27] = 1;
							32'b????_?100_0000_0000_0000_0000_0000_0000:	wl[26] = 1;
							32'b????_??10_0000_0000_0000_0000_0000_0000:	wl[25] = 1;
							32'b????_???1_0000_0000_0000_0000_0000_0000:	wl[24] = 1;
							32'b????_????_1000_0000_0000_0000_0000_0000:	wl[23] = 1;
							32'b????_????_?100_0000_0000_0000_0000_0000:	wl[22] = 1;
							32'b????_????_??10_0000_0000_0000_0000_0000:	wl[21] = 1;
							32'b????_????_???1_0000_0000_0000_0000_0000:	wl[20] = 1;
							32'b????_????_????_1000_0000_0000_0000_0000:	wl[19] = 1;
							32'b????_????_????_?100_0000_0000_0000_0000:	wl[18] = 1;
							32'b????_????_????_??10_0000_0000_0000_0000:	wl[17] = 1;
							32'b????_????_????_???1_0000_0000_0000_0000:	wl[16] = 1;
							32'b????_????_????_????_1000_0000_0000_0000:	wl[15] = 1;
							32'b????_????_????_????_?100_0000_0000_0000:	wl[14] = 1;
							32'b????_????_????_????_??10_0000_0000_0000:	wl[13] = 1;
							32'b????_????_????_????_???1_0000_0000_0000:	wl[12] = 1;
							32'b????_????_????_????_????_1000_0000_0000:	wl[11] = 1;
							32'b????_????_????_????_????_?100_0000_0000:	wl[10] = 1;
							32'b????_????_????_????_????_??10_0000_0000:	wl[9] = 1;
							32'b????_????_????_????_????_???1_0000_0000:	wl[8] = 1;
							32'b????_????_????_????_????_????_1000_0000:	wl[7] = 1;
							32'b????_????_????_????_????_????_?100_0000:	wl[6] = 1;
							32'b????_????_????_????_????_????_??10_0000:	wl[5] = 1;
							32'b????_????_????_????_????_????_???1_0000:	wl[4] = 1;
							32'b????_????_????_????_????_????_????_1000:	wl[3] = 1;
							32'b????_????_????_????_????_????_????_?100:	wl[2] = 1;
							32'b????_????_????_????_????_????_????_??10:	wl[1] = 1;
							32'b????_????_????_????_????_????_????_???1:	wl[0] = 1;
							32'b0000_0000_0000_0000_0000_0000_0000_0000:		// have to evict
								begin
									wl[next_evict] = 1;
									c_next_evict = r_next_evict+1;
								end
							endcase
						end
					endcase
				end
			end
		end
	
		always @(posedge clk) begin
			r_next_evict <= (reset?0:c_next_evict);
		end
			
		wire [NSETS-1:0]match[0:READPORTS-1];
		for (S = 0; S < NSETS; S=S+1) begin
			wire [NPHYS-1:12]trd[0:READPORTS-1];
			wire [NPHYS-1:12]snoop_tag, write_tag;
`ifdef PSYNTH
			ic1_xdata #(.NPHYS(NPHYS))data(.clk(clk),
				.wen(wl[S]),
				.waddr(ic_raddr[11:ACACHE_LINE_SIZE]),
				.din(ic_rdata),
				.tin(ic_raddr[NPHYS-1:12]),
				.raddr_0(raddr[0][11:ACACHE_LINE_SIZE]),
				.dout_0(rd[0][S]),
				.tout_0(trd[0]),
				.raddr_1(raddr[1][11:ACACHE_LINE_SIZE]),
				.dout_1(rd[1][S]),
				.tout_1(trd[1]),
				.raddr_2(ic_snoop_addr[11:ACACHE_LINE_SIZE]),
				.tout_2(snoop_tag),
				.tout_3(write_tag));
`else
			reg   [NPHYS-1:12]r_tags[0:NENTRIES-1];
			reg [CACHE_LINE_SIZE-1:0]r_data[0:NENTRIES-1];
			for (R = 0; R < READPORTS; R=R+1) begin :r
				assign rd[R][S]     = r_data[raddr[R][11:ACACHE_LINE_SIZE]];
				assign trd[R]	    = r_tags[raddr[R][11:ACACHE_LINE_SIZE]];
			end
			assign snoop_tag = r_tags[ic_snoop_addr[11:ACACHE_LINE_SIZE]];
			assign write_tag = r_tags[ic_raddr[11:ACACHE_LINE_SIZE]];

			always @(posedge clk)
			if (wl[S]) begin
				r_data[ic_raddr[11:ACACHE_LINE_SIZE]] <= ic_rdata;
				r_tags[ic_raddr[11:ACACHE_LINE_SIZE]] <= ic_raddr[NPHYS-1:12];
			end
`endif
			assign match_snoop[S] = (r_valid[S][ic_snoop_addr[11:ACACHE_LINE_SIZE]]) && snoop_tag == ic_snoop_addr[NPHYS-1:12];
			assign current_valid[S] = r_valid[S][ic_snoop_addr[11:ACACHE_LINE_SIZE]];

			always @(*) begin
				if (match_snoop[S] && ic_snoop_addr_req) begin
					case (ic_snoop_snoop) // synthesis full_case
					SNOOP_READ_EXCLUSIVE,
					SNOOP_READ_INVALID:		begin
												s[S] = 1;
											end
					default:				begin
												s[S] = 0;
											end
					endcase
				end else begin
					s[S] = 0;
				end
			end

			assign match_rdline[S] = write_tag == ic_raddr[NPHYS-1:12];
			assign rdline_valid[S] = r_valid[S][ic_raddr[11:ACACHE_LINE_SIZE]];

			always @(posedge clk)
			if (reset) begin
				 r_valid[S] <= 0;
			end else begin
				if (wl[S]) begin	// FIXME - convince me that these are never the same bit
					r_valid[S][ic_raddr[11:ACACHE_LINE_SIZE]] <= 1;
				end 
				if (s[S]) 
					r_valid[S][ic_snoop_addr[11:ACACHE_LINE_SIZE]] <= 0;
			end

			for (R = 0; R < READPORTS; R=R+1) begin 
				assign match[R][S] = (r_valid[S][raddr[R][11:ACACHE_LINE_SIZE]]) && trd[R] == raddr[R][NPHYS-1:12];
			end
		end
		for (R = 0; R < READPORTS; R=R+1) begin :r
			assign rhit[R] = |match[R];

			if (NSETS == 16) begin
				always @(*) begin 
					casez (match[R]) // synthesis full_case parallel_case
					16'b????_????_????_???1: rdd[R] = rd[R][0];
					16'b????_????_????_??1?: rdd[R] = rd[R][1];
					16'b????_????_????_?1??: rdd[R] = rd[R][2];
					16'b????_????_????_1???: rdd[R] = rd[R][3];
	
					16'b????_????_???1_????: rdd[R] = rd[R][4];
					16'b????_????_??1?_????: rdd[R] = rd[R][5];
					16'b????_????_?1??_????: rdd[R] = rd[R][6];
					16'b????_????_1???_????: rdd[R] = rd[R][7];
	
					16'b????_???1_????_????: rdd[R] = rd[R][8];
					16'b????_??1?_????_????: rdd[R] = rd[R][9];
					16'b????_?1??_????_????: rdd[R] = rd[R][10];
					16'b????_1???_????_????: rdd[R] = rd[R][11];
	
					16'b???1_????_????_????: rdd[R] = rd[R][12];
					16'b??1?_????_????_????: rdd[R] = rd[R][13];
					16'b?1??_????_????_????: rdd[R] = rd[R][14];
					16'b1???_????_????_????: rdd[R] = rd[R][15];
					default: rdd[R] = 512'bx;
					endcase
					case (raddr[R][5:4]) // synthesis full_case parallel_case
					0: rdata[R] = rdd[R][127:0];
					1: rdata[R] = rdd[R][255:128];
					2: rdata[R] = rdd[R][383:256];
					3: rdata[R] = rdd[R][511:384];
					endcase
				end
			end else begin
				always @(*) begin 
					casez (match[R]) // synthesis full_case parallel_case
					32'b????_????_????_????_????_????_????_???1: rdd[R] = rd[R][0];
					32'b????_????_????_????_????_????_????_??1?: rdd[R] = rd[R][1];
					32'b????_????_????_????_????_????_????_?1??: rdd[R] = rd[R][2];
					32'b????_????_????_????_????_????_????_1???: rdd[R] = rd[R][3];
	
					32'b????_????_????_????_????_????_???1_????: rdd[R] = rd[R][4];
					32'b????_????_????_????_????_????_??1?_????: rdd[R] = rd[R][5];
					32'b????_????_????_????_????_????_?1??_????: rdd[R] = rd[R][6];
					32'b????_????_????_????_????_????_1???_????: rdd[R] = rd[R][7];
	
					32'b????_????_????_????_????_???1_????_????: rdd[R] = rd[R][8];
					32'b????_????_????_????_????_??1?_????_????: rdd[R] = rd[R][9];
					32'b????_????_????_????_????_?1??_????_????: rdd[R] = rd[R][10];
					32'b????_????_????_????_????_1???_????_????: rdd[R] = rd[R][11];
	
					32'b????_????_????_????_???1_????_????_????: rdd[R] = rd[R][12];
					32'b????_????_????_????_??1?_????_????_????: rdd[R] = rd[R][13];
					32'b????_????_????_????_?1??_????_????_????: rdd[R] = rd[R][14];
					32'b????_????_????_????_1???_????_????_????: rdd[R] = rd[R][15];
	
					32'b????_????_????_???1_????_????_????_????: rdd[R] = rd[R][16];
					32'b????_????_????_??1?_????_????_????_????: rdd[R] = rd[R][17];
					32'b????_????_????_?1??_????_????_????_????: rdd[R] = rd[R][18];
					32'b????_????_????_1???_????_????_????_????: rdd[R] = rd[R][19];
	
					32'b????_????_???1_????_????_????_????_????: rdd[R] = rd[R][20];
					32'b????_????_??1?_????_????_????_????_????: rdd[R] = rd[R][21];
					32'b????_????_?1??_????_????_????_????_????: rdd[R] = rd[R][22];
					32'b????_????_1???_????_????_????_????_????: rdd[R] = rd[R][23];
	
					32'b????_???1_????_????_????_????_????_????: rdd[R] = rd[R][24];
					32'b????_??1?_????_????_????_????_????_????: rdd[R] = rd[R][25];
					32'b????_?1??_????_????_????_????_????_????: rdd[R] = rd[R][26];
					32'b????_1???_????_????_????_????_????_????: rdd[R] = rd[R][27];
	
					32'b???1_????_????_????_????_????_????_????: rdd[R] = rd[R][28];
					32'b??1?_????_????_????_????_????_????_????: rdd[R] = rd[R][29];
					32'b?1??_????_????_????_????_????_????_????: rdd[R] = rd[R][30];
					32'b1???_????_????_????_????_????_????_????: rdd[R] = rd[R][31];
					default: rdd[R] = 512'bx;
					endcase
					case (raddr[R][5:4]) // synthesis full_case parallel_case
					0: rdata[R] = rdd[R][127:0];
					1: rdata[R] = rdd[R][255:128];
					2: rdata[R] = rdd[R][383:256];
					3: rdata[R] = rdd[R][511:384];
					endcase
				end
			end
		end
	endgenerate

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
