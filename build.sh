#!/bin/bash

# Set the BEEBASM executable for the platform
BEEBASM=tools/beebasm/beebasm.exe
if [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
    BEEBASM=tools/beebasm/beebasm
fi

# Assember the ROM
$BEEBASM -i src/atomlcd.asm -v 2>&1 | tee ATOMLCD.log

# Convert to srecords
srec_cat ATOMLCD.rom -Binary -offset 0x2c00 -crlf -data-only > ATOMLCD.srec

ls -l ATOMLCD*
