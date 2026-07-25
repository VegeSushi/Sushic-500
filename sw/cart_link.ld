MEMORY {
    CART: start = $8000, size = $4000, type = ro, file = %O, fill = yes, fillval = $EA;
}
SEGMENTS {
    CODE: load = CART, type = ro;
}