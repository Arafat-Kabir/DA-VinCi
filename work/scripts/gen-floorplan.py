#!/bin/python3

#############################################################################
# This script generates the pblock placement script for                     #
# impl_davinci_wrapper_opt.tcl The generated Tcl script should be sourced   #
# after synthesis.                                                          #
#############################################################################


from string import Template

# Template variables
#   pbname             : pblock name
#   tileinst           : tile instance name
#   sliceLeft, sliceLow: site X and Y coordinate of lower-left corner
#   sliceRight, sliceUp: site X and Y coordinate of upper-right corner
#   bramLeft, bramLow  : site X and Y coordinate of lower-left corner
#   bramRight, bramUp  : site X and Y coordinate of upper-right corner
gemv_pblock_template = Template(
'''startgroup
create_pblock       $pbname
add_cells_to_pblock $pbname [get_cells [list {$tileinst}]] -clear_locs
resize_pblock       $pbname  -add {SLICE_X${sliceLeft}Y${sliceLow}:SLICE_X${sliceRight}Y${sliceUp}  RAMB18_X${bramLeft}Y${bramLow}:RAMB18_X${bramRight}Y${bramUp}}
endgroup'''
)

vv_pblock_template = Template(
'''startgroup
create_pblock       $pbname
add_cells_to_pblock $pbname [get_cells [list {$tileinst}]] -clear_locs
resize_pblock       $pbname  -add {SLICE_X${sliceLeft}Y${sliceLow}:SLICE_X${sliceRight}Y${sliceUp}  RAMB18_X${bramLeft}Y${bramLow}:RAMB18_X${bramRight}Y${bramUp}  DSP48E2_X${dspLeft}Y${dspLow}:DSP48E2_X${dspRight}Y${dspUp}}
endgroup'''
)


# Given the coordinates of the GEMV tile and sites, returns
# a dictionary to be used with the pblock template.
# Parameters: 
#   tile: (row, col)
#   sliceLL, sliceUR: (X, Y) of slice site
#   bramLL, bramUR: (X, Y) of bram site
#   dspLL, dspUR: (X, Y) of dsp site
def makeGemvTileSiteDict(tile, sliceLL, sliceUR, bramLL, bramUR):
    tile_dict = {
        'pbname'    : f'pb_tile_r{tile[0]}_c{tile[1]}',
        'tileinst'  : f'gemvArr/tile_row[{tile[0]}].tile_col[{tile[1]}].tile_inst',
        'sliceLeft' : sliceLL[0],
        'sliceLow'  : sliceLL[1],
        'sliceRight': sliceUR[0],
        'sliceUp'   : sliceUR[1],

        'bramLeft' : bramLL[0],
        'bramLow'  : bramLL[1],
        'bramRight': bramUR[0],
        'bramUp'   : bramUR[1],
    }
    return tile_dict


# Given the coordinates of the VV-tile and sites, returns
# a dictionary to be used with the pblock template.
# Parameters: 
#   tile: row
#   sliceLL, sliceUR: (X, Y) of slice site
#   bramLL, bramUR: (X, Y) of bram site
def makeVVTileSiteDict(tile, sliceLL, sliceUR, bramLL, bramUR, dspLL, dspUR):
    tile_dict = {
        'pbname'    : f'pb_vtile_r{tile}',
        'tileinst'  : f'vvtArr/tile[{tile}].vectile',
        'sliceLeft' : sliceLL[0],
        'sliceLow'  : sliceLL[1],
        'sliceRight': sliceUR[0],
        'sliceUp'   : sliceUR[1],

        'bramLeft' : bramLL[0],
        'bramLow'  : bramLL[1],
        'bramRight': bramUR[0],
        'bramUp'   : bramUR[1],

        'dspLeft' : dspLL[0],
        'dspLow'  : dspLL[1],
        'dspRight': dspUR[0],
        'dspUp'   : dspUR[1],
    }
    return tile_dict




# Site ranges: Corresponding indices can be placed together
# SliceX: these are visually checked values
# SliceY: these slices are aligned with BRAM blocks needed for a tile
# bramX : 1 BRAM column for a tile
# bramY : 24 BRAMs for a tile
tileRows_cnt = 12
tileCols_cnt = 14
site_ranges = {
    'sliceX': [(0,11), (12, 20),  (28, 39),   (45, 56), (57, 65), (81, 90), (91, 99), (107, 116), (117, 126), (137, 145), (146, 154), (167, 190), (206, 220), (221, 232)],
    'sliceY': [(i*60, i*60+59) for i in range(tileRows_cnt)],     # every 60 SLICE_Y
    'bramX' : [(i,i) for i in range(tileCols_cnt)],
    'bramY' : [(i*24,i*24+23) for i in range(tileRows_cnt)],
}

# reversing Y-ordinate makes tile-0-0 to be placed at top-left of the device
site_ranges['sliceY'].reverse()
site_ranges['bramY'].reverse()
site_ranges['dspY'] = [(max(r-6, 0), max(c-6, 0)) for r,c in site_ranges['bramY']]  # a quick hack for U55, max(c,0) to avoid negative numbers
# print(site_ranges['dspY'])




# -- gemvArr pblocks
gemvRows = 144//12
gemvCols = 26//2
for r in range(gemvRows):
    for c in range(gemvCols):
        tile_rc = (r,c)
        sliceLL = (site_ranges['sliceX'][c+1][0], site_ranges['sliceY'][r][0])  # c+1 saves the first column for the vvblock-array
        sliceUR = (site_ranges['sliceX'][c+1][1], site_ranges['sliceY'][r][1])
        bramLL  = (site_ranges['bramX'][c+1][0], site_ranges['bramY'][r][0])
        bramUR  = (site_ranges['bramX'][c+1][1], site_ranges['bramY'][r][1])
        tile_dict = makeGemvTileSiteDict(tile_rc, sliceLL, sliceUR, bramLL, bramUR)
        # print(tile_dict)
        pb_script = gemv_pblock_template.substitute(tile_dict)
        print(pb_script, '\n')


# -- vvtArr pblocks
vvRows = 144//12
for r in range(vvRows):
    tile = r
    sliceLL = (site_ranges['sliceX'][0][0], site_ranges['sliceY'][r][0])
    sliceUR = (site_ranges['sliceX'][0][1], site_ranges['sliceY'][r][1])
    bramLL  = (site_ranges['bramX'][0][0], site_ranges['bramY'][r][0])
    bramUR  = (site_ranges['bramX'][0][1], site_ranges['bramY'][r][1])
    dspLL   = (0, site_ranges['dspY'][r][0])    # always uses the left-most DSP column
    dspUR   = (0, site_ranges['dspY'][r][1])
    tile_dict = makeVVTileSiteDict(tile, sliceLL, sliceUR, bramLL, bramUR, dspLL, dspUR)
    # print(tile_dict)
    pb_script = vv_pblock_template.substitute(tile_dict)
    print(pb_script, '\n')



