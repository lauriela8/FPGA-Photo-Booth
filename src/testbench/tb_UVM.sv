`timescale 1ns / 1ps

// ============================================================
// 1) Write-stream 인터페이스 (VGA_Cartoon DUT 포트에 매칭)
// ============================================================
interface vga_wr_intf;
    logic        clk;
    logic        reset;  // active-high
    // to DUT (camera write stream)
    logic        we_in;
    logic [16:0] wAddr_in;
    logic [15:0] wData_in;  // RGB565
    // from DUT (to frame buffer)
    logic        we_out;
    logic [16:0] wAddr_out;
    logic [15:0] wData_out;
endinterface

// ============================================================
// 2) Transaction : 1클럭 단위 write beat
// ============================================================
class wr_txn;
    rand bit        we;
    rand bit [16:0] addr;
    rand bit [15:0] data;
    int             idx;  // 0..(W*H-1)
endclass

// ============================================================
// 3) Generator : 320x240 1프레임, 픽셀마다 랜덤 RGB565 데이터
// ============================================================
class generator;
    mailbox #(wr_txn) gen2drv_mbox;

    localparam int W = 320;
    localparam int H = 240;
    localparam int N = W * H;

    localparam int FRAMES_TO_RUN = 1;

    function new(mailbox#(wr_txn) gen2drv_mbox);
        this.gen2drv_mbox = gen2drv_mbox;
    endfunction

    task put(bit we, bit [16:0] a, bit [15:0] d, int i);
        wr_txn t = new();
        t.we   = we;
        t.addr = a;
        t.data = d;
        t.idx  = i;
        gen2drv_mbox.put(t);
    endtask

    task run();
        for (int f = 0; f < FRAMES_TO_RUN; f++) begin
            for (int i = 0; i < N; i++) begin
                bit [15:0] rand_pix;
                rand_pix = $random;   // XSim 호환: $urandom 대신 $random
                put(1'b1, 17'(i), rand_pix, i);
            end
            // 프레임 끝나고 we=0 버블
            for (int k = 0; k < 50; k++) put(1'b0, '0, '0, -1);
        end
    endtask
endclass

// ============================================================
// 4) Driver : negedge에 구동 → posedge에서 DUT 샘플
// ============================================================
class driver;
    virtual vga_wr_intf vif;
    mailbox #(wr_txn)   gen2drv_mbox;

    function new(mailbox#(wr_txn) gen2drv_mbox, virtual vga_wr_intf vif);
        this.gen2drv_mbox = gen2drv_mbox;
        this.vif          = vif;
    endfunction

    task run();
        wr_txn tr;
        forever begin
            gen2drv_mbox.get(tr);
            @(negedge vif.clk);
            vif.we_in    <= tr.we;
            vif.wAddr_in <= tr.addr;
            vif.wData_in <= tr.data;
            @(posedge vif.clk);
        end
    endtask
endclass

// ============================================================
// 5) Monitor : 입력만 SB로 전달 (출력은 SB가 직접 읽음)
// ============================================================
class monitor;
    virtual vga_wr_intf vif;
    mailbox #(wr_txn)   mon2scb_mbox;

    function new(mailbox#(wr_txn) mon2scb_mbox, virtual vga_wr_intf vif);
        this.mon2scb_mbox = mon2scb_mbox;
        this.vif          = vif;
    endfunction

    task run();
        wr_txn tr;
        forever begin
            @(posedge vif.clk);
            tr = new();
            tr.we   = vif.we_in;
            tr.addr = vif.wAddr_in;
            tr.data = vif.wData_in;
            tr.idx  = -1;
            mon2scb_mbox.put(tr);
        end
    endtask
endclass

// ============================================================
// 6) Scoreboard : 3클럭 정렬 확인 (WE/ADDR만 기본 검사)
//   ※ 필터로 데이터가 바뀌므로 CHECK_DATA=0이 기본
// ============================================================
class scoreboard;
    virtual vga_wr_intf vif;
    mailbox #(wr_txn)   mon2scb_mbox;

    // 필요 시 1로 바꾸면 DATA 비교도 수행
    bit CHECK_DATA = 1'b0;

    typedef struct packed {
        bit        we;
        bit [16:0] a;
        bit [15:0] d;
    } beat_t;
    beat_t q[3];

    int total_checks, total_mismatch;

    function new(mailbox#(wr_txn) mon2scb_mbox, virtual vga_wr_intf vif);
        this.mon2scb_mbox = mon2scb_mbox;
        this.vif          = vif;
    endfunction

    task run();
        wr_txn        tr;
        beat_t        exp;
        bit           we_s;
        bit    [16:0] a_s;
        bit    [15:0] d_s;

        total_checks   = 0;
        total_mismatch = 0;

        q[0] = '{we:0,a:'0,d:'0};
        q[1] = '{we:0,a:'0,d:'0};
        q[2] = '{we:0,a:'0,d:'0};

        forever begin
            mon2scb_mbox.get(tr);

            // 3-stage delay line for expected timing
            q[2] = q[1];
            q[1] = q[0];
            q[0] = '{we: tr.we, a: tr.addr, d: tr.data};

            exp  = q[2];

            // DUT outputs sampled same posedge
            we_s = vif.we_out;
            a_s  = vif.wAddr_out;
            d_s  = vif.wData_out;

            if (exp.we) begin
                total_checks++;

                if (we_s !== 1'b1) begin
                    total_mismatch++;
                    $display("**WE MISMATCH** got=%0b exp=1 (time=%0t)",
                              we_s, $time);
                end
                if (a_s !== exp.a) begin
                    total_mismatch++;
                    $display("**ADDR MISMATCH** got=%0d exp=%0d (time=%0t)",
                              a_s, exp.a, $time);
                end

                if (CHECK_DATA) begin
                    if (d_s !== exp.d) begin
                        total_mismatch++;
                        $display("**DATA MISMATCH** got=0x%04h exp=0x%04h (time=%0t)",
                                  d_s, exp.d, $time);
                    end
                end
            end
        end
    endtask
endclass

// ============================================================
// 7) Environment : gen/driver/monitor/scoreboard 연결
// ============================================================
class environment;
    generator           gen;
    driver              drv;
    monitor             mon;
    scoreboard          scb;
    mailbox #(wr_txn)   gen2drv_mbox;
    mailbox #(wr_txn)   mon2scb_mbox;
    virtual vga_wr_intf vif;

    function new(virtual vga_wr_intf vif);
        this.vif = vif;
        gen2drv_mbox = new();
        mon2scb_mbox = new();
        gen = new(gen2drv_mbox);
        drv = new(gen2drv_mbox, vif);
        mon = new(mon2scb_mbox, vif);
        scb = new(mon2scb_mbox, vif);
    endfunction

    task run();
        fork
            gen.run();
            drv.run();
            mon.run();
            scb.run();
        join_none
    endtask
endclass

// ============================================================
// 8) Top TB : DUT + 클럭/리셋 + env + 커버리지 + final 리포트
// ============================================================
module tb_vga_cartoon_uvmstyle;
    vga_wr_intf vif ();
    environment env;

    // ---- DUT 파라미터(여기 값이 커버그룹에서도 쓰이므로 TB 쪽에 상수로 보관) ----
    localparam int IMG_W_TB   = 320;
    localparam int IMG_H_TB   = 240;
    localparam int KEEP_RB_TB = 2;
    localparam int KEEP_G_TB  = 2;
    localparam int EDGE_THR_TB= 50;

    Cartoon_Filter #(
        .IMG_WIDTH (IMG_W_TB),
        .IMG_HEIGHT(IMG_H_TB),
        .KEEP_RB_MSBS(KEEP_RB_TB),
        .KEEP_G_MSBS (KEEP_G_TB),
        .EDGE_THR    (EDGE_THR_TB)
    ) dut (
        .clk      (vif.clk),
        .reset    (vif.reset),
        .we_in    (vif.we_in),
        .wAddr_in (vif.wAddr_in),
        .wData_in (vif.wData_in),
        .we_out   (vif.we_out),
        .wAddr_out(vif.wAddr_out),
        .wData_out(vif.wData_out)
    );

    // Clock
    localparam real CLK_PERIOD_NS = 20.0;  // 50 MHz
    initial vif.clk = 1'b0;
    always #(CLK_PERIOD_NS / 2.0) vif.clk = ~vif.clk;

    // --------------------------------------------------------
    // Coverage용 경계 플래그 정렬 (출력 we_out 타이밍 기준)
    // DUT에 at_border_d2가 있으므로 TB에서 1clk 지연 → *_d3 역할
    // --------------------------------------------------------
    logic border_d3_tb;
    always_ff @(posedge vif.clk or posedge vif.reset) begin
        if (vif.reset) border_d3_tb <= 1'b0;
        else           border_d3_tb <= dut.at_border_d2;
    end

    // ========================================================
    // Functional Coverage (Covergroups)
    // ========================================================

    // (1) Border vs Inner
    covergroup cg_border @(posedge vif.clk);
        option.per_instance = 1;
        border_cp : coverpoint border_d3_tb iff (vif.we_out) {
            bins inner  = {0};
            bins border = {1};
        }
    endgroup
    cg_border cov_border = new;

    // (2) Edge magnitude & overlay occurrence
    covergroup cg_edge @(posedge vif.clk);
        option.per_instance = 1;
        // 내부 픽셀만
        edge_mag_cp : coverpoint dut.edge_mag
            iff (vif.we_out && !border_d3_tb) {
            bins zero = {0};
            bins low  = {[1:EDGE_THR_TB-1]};
            bins hit  = {[EDGE_THR_TB:$]};
        }
        overlay_cp : coverpoint (dut.edge_mag >= EDGE_THR_TB)
            iff (vif.we_out && !border_d3_tb) {
            bins off = {0};
            bins on  = {1};
        }
        edge_x_overlay : cross edge_mag_cp, overlay_cp;
    endgroup
    cg_edge cov_edge = new;

    // (3) Orientation (vertical / horizontal / diagonal-ish)
    covergroup cg_orient @(posedge vif.clk);
        option.per_instance = 1;
        vertical_cp : coverpoint
            (dut.abs_gx > (dut.abs_gy << 1))
            iff (vif.we_out && !border_d3_tb) { bins no={0}; bins yes={1}; }
        horizontal_cp : coverpoint
            (dut.abs_gy > (dut.abs_gx << 1))
            iff (vif.we_out && !border_d3_tb) { bins no={0}; bins yes={1}; }
        diagonal_cp : coverpoint
            ( !(dut.abs_gx > (dut.abs_gy << 1)) &&
              !(dut.abs_gy > (dut.abs_gx << 1)) )
            iff (vif.we_out && !border_d3_tb) { bins no={0}; bins yes={1}; }
    endgroup
    cg_orient cov_orient = new;

    // (4) WE 패턴 (연속/버블/유휴)
    covergroup cg_we @(posedge vif.clk);
        option.per_instance = 1;
        we_seq : coverpoint vif.we_out {
            bins burst = (1 [*5:100]);
            bins gap   = (1 [*1:50] => 0 [*1:10] => 1);
            bins idle  = (0 [*5:100]);
        }
    endgroup
    cg_we cov_we = new;

    // (5) Parameter sweep coverage (멀티 런 병합용)
    covergroup cg_params @(posedge vif.clk);
        option.per_instance = 1;
        KEEP_RB : coverpoint KEEP_RB_TB { bins keep[] = {1,2,3,4,5}; }
        KEEP_G  : coverpoint KEEP_G_TB  { bins keep[] = {1,2,3,4,5,6}; }
        cross KEEP_RB, KEEP_G;
    endgroup
    cg_params cov_params = new;

    // Reset & run
    initial begin
        $srandom(32'hC0FFEE11);

        // 초기값
        vif.reset    = 1'b1;
        vif.we_in    = 1'b0;
        vif.wAddr_in = '0;
        vif.wData_in = '0;

        // 리셋
        repeat (8) @(posedge vif.clk);
        vif.reset = 1'b0;
        repeat (4) @(posedge vif.clk);

        // Env run
        env = new(vif);
        env.run();

        // 타임아웃
        repeat (200000) @(posedge vif.clk);
        $display("\n[TB] Timeout finish");
        $finish;
    end

    // ===== Functional coverage auto-report at sim end =====
    final begin
      real c_border   = cov_border.get_coverage();
      real c_edge     = cov_edge.get_coverage();
      real c_orient   = cov_orient.get_coverage();
      real c_we       = cov_we.get_coverage();
      real c_params   = cov_params.get_coverage();
      real c_overall  = (c_border + c_edge + c_orient + c_we + c_params) / 5.0;

      
      $display("\n=========================[COVERAGE]=========================");
      $display("Simulation finished at %0t", $time);
      $display("Border        : %0.2f%%", c_border  );
      $display("Edge Magnitude: %0.2f%%", c_edge    );
      $display("Orientation   : %0.2f%%", c_orient  );
      //$display("[COVERAGE] WE Pattern    : %0.2f%%", c_we      );
      //$display("[COVERAGE] Param Sweep   : %0.2f%%", c_params  );
      //$display("[COVERAGE] Overall(Avg)  : %0.2f%%", c_overall );
      $display("============================================================\n");

      // 상세 bin 리포트가 필요하면 아래 주석 해제
      // cov_border.print();
      // cov_edge.print();
      // cov_orient.print();
      // cov_we.print();
      // cov_params.print();
    end

    // VCD
    initial begin
        $dumpfile("tb_vga_cartoon_uvmstyle.vcd");
        $dumpvars(0, tb_vga_cartoon_uvmstyle);
    end
endmodule
