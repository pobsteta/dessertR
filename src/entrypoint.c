// We need to forward routine registration from C to Rust
// to avoid the linker removing the static library.

void R_init_dessert_r_extendr(void *dll);
void register_extendr_panic_hook(void);

// Le nom du paquet (dessertR, casse mixte) n'est pas un identifiant Rust valide :
// la crate expose donc R_init_dessert_r_extendr, mais R charge dessertR.so et
// appelle R_init_dessertR. On fait le pont ici, sinon les routines natives ne
// sont jamais enregistrees (.Call introuvable).
void R_init_dessertR(void *dll) {
    register_extendr_panic_hook();
    R_init_dessert_r_extendr(dll);
}
