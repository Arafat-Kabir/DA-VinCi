# Removed GEMV blocks
startgroup
create_pblock       pb_tile_r9_c11
add_cells_to_pblock pb_tile_r9_c11 [get_cells [list {gemvArr/tile_row[9].tile_col[11].tile_inst}]] -clear_locs
resize_pblock       pb_tile_r9_c11  -add {SLICE_X206Y120:SLICE_X220Y179  RAMB18_X12Y48:RAMB18_X12Y71}
endgroup 

startgroup
create_pblock       pb_tile_r9_c12
add_cells_to_pblock pb_tile_r9_c12 [get_cells [list {gemvArr/tile_row[9].tile_col[12].tile_inst}]] -clear_locs
resize_pblock       pb_tile_r9_c12  -add {SLICE_X221Y120:SLICE_X232Y179  RAMB18_X13Y48:RAMB18_X13Y71}
endgroup 


# Removed VV blocks
startgroup
create_pblock       pb_vtile_r2
add_cells_to_pblock pb_vtile_r2 [get_cells [list {vvtArr/tile[2].vectile}]] -clear_locs
resize_pblock       pb_vtile_r2  -add {SLICE_X0Y540:SLICE_X11Y599  RAMB18_X0Y216:RAMB18_X0Y239  DSP48E2_X0Y210:DSP48E2_X0Y233}
endgroup 

startgroup
create_pblock       pb_vtile_r8
add_cells_to_pblock pb_vtile_r8 [get_cells [list {vvtArr/tile[8].vectile}]] -clear_locs
resize_pblock       pb_vtile_r8  -add {SLICE_X0Y180:SLICE_X11Y239  RAMB18_X0Y72:RAMB18_X0Y95  DSP48E2_X0Y66:DSP48E2_X0Y89}
endgroup 

startgroup
create_pblock       pb_vtile_r9
add_cells_to_pblock pb_vtile_r9 [get_cells [list {vvtArr/tile[9].vectile}]] -clear_locs
resize_pblock       pb_vtile_r9  -add {SLICE_X0Y120:SLICE_X11Y179  RAMB18_X0Y48:RAMB18_X0Y71  DSP48E2_X0Y42:DSP48E2_X0Y65}
endgroup 

