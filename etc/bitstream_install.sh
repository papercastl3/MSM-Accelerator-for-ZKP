#!/bin/bash
sudo xmutil unloadapp 2>/dev/null
sudo fpgautil -b ./TopDesign1_wrapper.bit -f Full
sudo cat /sys/class/fpga_manager/fpga0/state