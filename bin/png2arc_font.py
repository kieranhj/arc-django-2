#!/usr/bin/python
import png,argparse,sys,math,arc

##########################################################################
##########################################################################

# Read 1 byte from our input file
def get_byte(file):
    return ord(file.read(1))

def save_file(data,path):
    if path is not None:
        with open(path,'wb') as f:
            f.write(''.join([chr(x) for x in data]))

##########################################################################
##########################################################################

def get_palette(boxed_row_flat_pixel):
    palette = []
    for row in boxed_row_flat_pixel:
        for i in range(0,len(row),4):
            rgb = [row[i+0],row[i+1],row[i+2]]
            if rgb not in palette:
                palette.append(rgb)
            
    return palette

##########################################################################
##########################################################################

def find_closest_match(palette, rgb):
    # Do this the lame non-Pythonic way. I'm sure this could be a single line blah blah.
    closest_idx = -1
    closest_dist = 256*256
    for i in range(16):
        col = palette[i]
        dist = (rgb[0]-col[0])*(rgb[0]-col[0])
        + (rgb[1]-col[1])*(rgb[1]-col[2])
        + (rgb[2]-col[2])*( rgb[2]-col[2])
        if dist < closest_dist:
            closest_idx = i
            closest_dist = dist

    return closest_idx

def to_box_row_palette_indices(boxed_row_flat_pixel, palette, closest_match):
    pidxs = []
    for row in boxed_row_flat_pixel:
        pidxs.append([])
        for i in range(0,len(row),4):
            rgb = [row[i+0],row[i+1],row[i+2]]
            # Prefer towards the end of the palette?
            # Probably unless zero?
            try:
                idx_last = len(palette) - palette[::-1].index(rgb) - 1
            except:
                idx_last = find_closest_match(palette, rgb)

            pidxs[-1].append(idx_last)

    return pidxs

##########################################################################
##########################################################################

def main(options):
    # Only support MODE 9 for now. MODE 13 coming later.
    if options.mode != 9:
        print>>sys.stderr,'FATAL: invalid mode: %d.'%options.mode
        sys.exit(1)

    pixels_per_byte=2
    pack=arc.pack_4bpp

    png_result=png.Reader(filename=options.input_path).asRGBA8()

    src_width=png_result[0]
    src_height=png_result[1]
    print 'Source image width: {0} height: {1}.'.format(src_width,src_height)

    palette = get_palette(png_result[2])
    print 'Found {0} palette entries in source image.'.format(len(palette))
    
    if len(palette) > 16:
        print>>sys.stderr,'FATAL: too many colours: %d.'%len(palette)
        sys.exit(1)

    if options.use_palette is not None:
        # Open palette binary file.
        palette_file = open(options.use_palette, 'rb')

        palette=[]
        for i in range(16):
            r = get_byte(palette_file)
            g = get_byte(palette_file)
            b = get_byte(palette_file)
            a = get_byte(palette_file)
            palette.append([r, g, b])

    else:
        # Sort palette by (greyscale) intensity.
        # palette.sort(key=lambda e: e[0]*e[0]+e[1]*e[1]+e[2]*e[2])
        palette.sort(key=lambda e: 0.299*e[0] + 0.587*e[1] + 0.114*e[2])


        if len(palette) < 16:
            # Prefer entry 0 to be black, if not already.
            if palette[0] != [0, 0, 0]:
                palette.insert(0, [0, 0, 0])

        # Prefer last entry to be white, if not already.
        if len(palette) < 16:
            if palette[-1] != [255, 255, 255]:
                palette.append([255, 255, 255])

        # Pad end of palette with white:
        while len(palette) < 16:
            palette.append([255, 255, 255])

    # Reading the file again seems wrong? This is OK now we have a separate palette?
    png_result=png.Reader(filename=options.input_path).asRGBA8()

    if options.loud:
        print(palette)
        
    pixels = to_box_row_palette_indices(png_result[2], palette, options.closest_match)
    assert(len(pixels)==src_height)

    print 'Glyph dimensions {0} x {1} pixels.'.format(options.glyph_dim[0], options.glyph_dim[1])

    glyphs_across=src_width/options.glyph_dim[0]
    glyphs_down=src_height/options.glyph_dim[1]
    glyph_size=options.glyph_dim[0]*options.glyph_dim[1]/pixels_per_byte
    # TODO: Warning/errors if not a multiple of src_width/src_height.
    # TODO: Handle if glyph width is not a clean multiple of words.

    print 'Max glyphs {0} x {1} = {2}.'.format(glyphs_across, glyphs_down, glyphs_across*glyphs_down)

    pixel_data=[]
    num_glyphs=0

    # Assume this is a standard block of glyphs.
    for glyph_top in range(0,src_height,options.glyph_dim[1]):
        for glyph_left in range(0,src_width,options.glyph_dim[0]):

            if options.max_glyphs is not None and num_glyphs>=options.max_glyphs:
                break

            # One glyph.
            for y in range(0,options.glyph_dim[1]):
                row=pixels[glyph_top+y]
                assert(len(row)==src_width)
                for x in range(0,options.glyph_dim[0],pixels_per_byte):
                    xs=[]
                    for p in range(0,pixels_per_byte):
                        xs.append(row[glyph_left+x+p])
                    assert len(xs)==pixels_per_byte
                    pixel_data.append(pack(xs))
            
            num_glyphs+=1
            
    assert(len(pixel_data)==num_glyphs*glyph_size)
    save_file(pixel_data,options.output_path)
    print 'Wrote {0} glyphs at {1} bytes per glyph for a total of {2} bytes of Arc data.'.format(num_glyphs, glyph_size, len(pixel_data))

    if options.palette_path is not None:
        pal_data=[]
        for p in palette:
            warned=False
            for i in range(0,3):
                if (p[i] & 0x0f) != 0 and not warned:
                    if options.loud:
                        print 'Warning: lost precision for colour',p
                    warned=True
                pal_data.append(p[i] & 0xf0)
            pal_data.append(0)
        assert(len(pal_data)==4*len(palette))
        save_file(pal_data,options.palette_path)
        print 'Wrote {0} bytes palette data.'.format(len(pal_data))


##########################################################################
##########################################################################

if __name__=='__main__':
    parser=argparse.ArgumentParser()

    parser.add_argument('-o',dest='output_path',metavar='FILE',help='output ARC data to %(metavar)s')
    parser.add_argument('-p',dest='palette_path',metavar='FILE',help='output palette data to %(metavar)s')
    parser.add_argument('--loud',action='store_true',help='display warnings')
    parser.add_argument('--glyph-dim',
                        default=None,
                        type=int,
                        nargs=2,
                        help='specify dimensions of a single glyph')
    parser.add_argument('--max-glyphs',
                        default=None,
                        type=int,
                        help='maximum number of glyphs to save')
    parser.add_argument('--use-palette',dest='use_palette',metavar='FILE',help='use palette binary data from %(metavar)s')
    parser.add_argument('--closest-match',action='store_true',help='match closest entry in palette if not exact.')
    parser.add_argument('input_path',metavar='FILE',help='load PNG data from %(metavar)s')
    parser.add_argument('mode',type=int,help='screen mode')
    main(parser.parse_args())
