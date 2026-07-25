MEMORY {
    ZP:  start = $0000, size = $0100, type = rw, file = "";
    RAM: start = $0200, size = $7E00, type = rw, file = "";
    ROM:     start = $D000, size = $2FFA, type = ro, file = %O, fill = yes, fillval = $EA;
    VECTORS: start = $FFFA, size = $0006, type = ro, file = %O, fill = yes, fillval = $EA;
}

SEGMENTS {
    ZEROPAGE: load = ZP,      type = zp, optional = yes;
    BSS:      load = RAM,     type = rw, optional = yes;
    CODE:     load = ROM,     type = ro, align = $100;
    VECTORS:  load = VECTORS, type = ro;
}