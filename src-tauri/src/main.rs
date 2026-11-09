// Pas de console noire en version finale
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    minima_studio_lib::run()
}
