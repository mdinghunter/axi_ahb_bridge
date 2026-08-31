onerror resume
wave tags  sim
wave update off
wave zoom range 0 765000
wave group tb_top.u_slave.bus.slave -backgroundcolor #004466
wave add -group tb_top.u_slave.bus.slave tb_top.u_slave.bus.HCLK -tag sim -radix hexadecimal -enumsymbolic 
wave add -group tb_top.u_slave.bus.slave tb_top.u_slave.bus.HRESETn -tag sim -radix hexadecimal -enumsymbolic 
wave add -group tb_top.u_slave.bus.slave tb_top.u_slave.bus.HADDR -tag sim -radix hexadecimal -enumsymbolic 
wave add -group tb_top.u_slave.bus.slave tb_top.u_slave.bus.HBURST -tag sim -radix mnemonic -enumsymbolic 
wave add -group tb_top.u_slave.bus.slave tb_top.u_slave.bus.HPROT -tag sim -radix hexadecimal -enumsymbolic 
wave add -group tb_top.u_slave.bus.slave tb_top.u_slave.bus.HSIZE -tag sim -radix mnemonic -enumsymbolic 
wave add -group tb_top.u_slave.bus.slave tb_top.u_slave.bus.HTRANS -tag sim -radix mnemonic -enumsymbolic 
wave add -group tb_top.u_slave.bus.slave tb_top.u_slave.bus.HWDATA -tag sim -radix hexadecimal -enumsymbolic 
wave add -group tb_top.u_slave.bus.slave tb_top.u_slave.bus.HWRITE -tag sim -radix hexadecimal -enumsymbolic 
wave add -group tb_top.u_slave.bus.slave tb_top.u_slave.bus.HRDATA -tag sim -radix hexadecimal -enumsymbolic 
wave add -group tb_top.u_slave.bus.slave tb_top.u_slave.bus.HREADYOUT -tag sim -radix hexadecimal -enumsymbolic 
wave add -group tb_top.u_slave.bus.slave tb_top.u_slave.bus.HRESP -tag sim -radix mnemonic -enumsymbolic 
wave add -group tb_top.u_slave.bus.slave tb_top.u_slave.bus.HREADY -tag sim -radix hexadecimal -enumsymbolic 
wave add -group tb_top.u_slave.bus.slave tb_top.u_slave.bus.HSEL -tag sim -radix hexadecimal -enumsymbolic 
wave insertion [expr [wave index insertpoint] + 1]
wave group tb_top.u_slave -backgroundcolor #006666
wave add -group tb_top.u_slave tb_top.u_slave.MEM_WORDS -tag sim -radix hexadecimal -enumsymbolic 
wave add -group tb_top.u_slave tb_top.u_slave.MAX_WAIT -tag sim -radix hexadecimal -enumsymbolic 
wave add -group tb_top.u_slave tb_top.u_slave.HWRITE_reg -tag sim -radix hexadecimal -enumsymbolic 
wave add -group tb_top.u_slave tb_top.u_slave.addr_phase -tag sim -radix hexadecimal -enumsymbolic 
wave add -group tb_top.u_slave tb_top.u_slave.valid_reg -tag sim -radix hexadecimal -enumsymbolic 
wave add -group tb_top.u_slave tb_top.u_slave.HREADYOUT_counter -tag sim -radix hexadecimal -enumsymbolic 
wave add -group tb_top.u_slave tb_top.u_slave.mem -tag sim -radix hexadecimal -enumsymbolic 
wave add -group tb_top.u_slave tb_top.u_slave.byte_enable -tag sim -radix hexadecimal -enumsymbolic 
wave add -group tb_top.u_slave tb_top.u_slave.byte_enable_reg -tag sim -radix hexadecimal -enumsymbolic 
wave add -group tb_top.u_slave tb_top.u_slave.mem_addr -tag sim -radix hexadecimal -enumsymbolic 
wave add -group tb_top.u_slave tb_top.u_slave.mem_addr_reg -tag sim -radix hexadecimal -enumsymbolic 
wave insertion [expr [wave index insertpoint] + 1]
wave update on
wave top 0
wave cursor add -name {Cursor 1} -time 765000ps -color Gold -restore -primary
wave cursor add -name {Cursor 2} -time 0ps -color Gold -restore -secondary
