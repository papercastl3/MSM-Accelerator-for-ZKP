we use FPGA Board KRIA KR260. The Vivado's Hardware manager connect to FPGA PS (to use ILA Debugging), the cpu was locked. so we search this issue and find the solution.

bootloader boot.scr.uimg and add "cpuidle.off=1" at kernel args.
