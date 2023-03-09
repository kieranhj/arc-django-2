ifeq ($(OS),Windows_NT)
RM_RF:=-cmd /c rd /s /q
MKDIR_P:=-cmd /c mkdir
COPY:=copy
VASM?=bin\vasmarm_std_win32.exe
VLINK?=bin\vlink.exe
LZ4?=bin\lz4.exe
PYTHON2?=C:\Dev\Python27\python.exe
PYTHON3?=python.exe
DOS2UNIX?=bin\dos2unix.exe
else
RM_RF:=rm -Rf
MKDIR_P:=mkdir -p
COPY:=cp
VASM?=vasmarm_std
VLINK?=vlink
LZ4?=lz4
PYTHON3?=python
DOS2UNIX?=dos2unix
endif

PNG2ARC=./bin/png2arc.py
PNG2ARC_FONT=./bin/png2arc_font.py
PNG2ARC_SPRITE=./bin/png2arc_sprite.py
PNG2ARC_DEPS:=./bin/png2arc.py ./bin/arc.py ./bin/png2arc_font.py ./bin/png2arc_sprite.py
FOLDER=!Django02
HOSTFS=../arculator/hostfs
# TODO: Need a copy command that copes with forward slash directory separator. (Maybe MSYS cp?)

##########################################################################
##########################################################################

.PHONY:deploy
deploy:folder
	$(RM_RF) "$(HOSTFS)\$(FOLDER)"
	$(MKDIR_P) "$(HOSTFS)\$(FOLDER)"
	$(COPY) "$(FOLDER)\*.*" "$(HOSTFS)\$(FOLDER)\*.*"

.PHONY:folder
folder: build loader music text
	$(RM_RF) $(FOLDER)
	$(MKDIR_P) $(FOLDER)
	$(COPY) .\folder\*.* "$(FOLDER)\*.*"
	$(COPY) .\build\!run.txt "$(FOLDER)\!Run,feb"
	$(COPY) .\build\icon.bin "$(FOLDER)\!Sprites,ff9"
	$(COPY) .\build\django01.txt "$(FOLDER)\!Help"
	$(COPY) .\build\arc-django.bin "$(FOLDER)\!RunImage,ff8"

.PHONY:loader
loader: build ./build/arc-django.lz4
	$(VASM) -L build/loader.txt -m250 -Fbin -opt-adr -o build\loader.bin src/loader.asm

./build/arc-django.bin: ./build/arc-django.o link_script.txt
	$(VLINK) -T link_script.txt -b rawbin1 -o $@ build/arc-django.o -Mbuild/linker.txt

./build/arc-django.o: build arc-django.asm assets music
	$(VASM) -L build/compile.txt -m250 -Fvobj -opt-adr -o build/arc-django.o arc-django.asm

.PHONY:assets
assets: build ./build/logo.lz4 ./data/logo-palette-hacked.bin ./build/big-font.bin \
	./build/rabenauge.lz4 ./build/rabenauge.bin.pal ./build/small-font.bin \
	./build/icon.bin ./build/logo.bin.mask

.PHONY:music
music: build ./build/music_01.bin ./build/music_02.bin ./build/music_03.bin \
	./build/music_04.bin ./build/music_05.bin ./build/music_06.bin \
	./build/music_07.bin ./build/music_08.bin ./build/music_09.bin \
	./build/music_10.bin ./build/music_splash.bin

.PHONY:text build
text: ./build/!run.txt ./build/django01.txt

build:
	$(MKDIR_P) "./build"

##########################################################################
##########################################################################

.PHONY:clean
clean:
	$(RM_RF) "build"
	$(RM_RF) "$(FOLDER)"

##########################################################################
##########################################################################

./build/arc-django.lz4: ./build/arc-django.bin

# TODO: Figure out how to not need to make the build dir for every target.
./build/logo.lz4: ./build/logo.bin
./build/logo.bin: ./data/gfx/chipodjangofina-10colors-216x68.png ./data/logo-palette-hacked.bin $(PNG2ARC_DEPS)
	$(PYTHON2) $(PNG2ARC) -o $@ --use-palette data/logo-palette-hacked.bin -m $@.mask --mask-colour 0x00ff0000 --loud $< 9

./build/big-font.bin: ./data/font/font-big-finalFINAL.png $(PNG2ARC_DEPS)
	$(PYTHON2) $(PNG2ARC_FONT) -o $@ --glyph-dim 16 16 $< 9

./build/small-font.bin: ./data/font/font-8x5-onelined.png $(PNG2ARC_DEPS)
	$(PYTHON2) $(PNG2ARC_FONT) -o $@ --glyph-dim 8 5 $< 9

./build/icon.bin: ./data/gfx/icon.png $(PNG2ARC_DEPS)
	$(PYTHON2) $(PNG2ARC_SPRITE) --name !django02 -o $@ $< 9

./build/rabenauge.lz4: ./build/rabenauge.bin
./build/rabenauge.bin: ./data/gfx/combined-logo.png $(PNG2ARC_DEPS)
	$(PYTHON2) $(PNG2ARC) -o $@ -p $@.pal $< 9

./build/bitshifters.lz4: ./build/bitshifters.bin
./build/bitshifters.bin: ./data/gfx/logo_flatplane04.png $(PNG2ARC_DEPS)
	$(PYTHON2) $(PNG2ARC) -o $@ -p $@.pal $< 9

##########################################################################
##########################################################################

./build/music_01.bin: ./data/music2/1IND-birdhouse-indahouz3.mod
	$(COPY) $(subst /,\\,$+) $(subst /,\\,$@)

./build/music_02.bin: ./data/music2/autumn-mood.mod
	$(COPY) $(subst /,\\,$+) $(subst /,\\,$@)

./build/music_03.bin: ./data/music2/ne7-square-circles.mod
	$(COPY) $(subst /,\\,$+) $(subst /,\\,$@)

./build/music_04.bin: ./data/music2/mod.okeanos-jesuisk.mod
	$(COPY) $(subst /,\\,$+) $(subst /,\\,$@)

./build/music_05.bin: ./data/music2/mod.okeanos-la_soupe_aux_choux.mod
	$(COPY) $(subst /,\\,$+) $(subst /,\\,$@)

./build/music_06.bin: ./data/music2/bodoaxian.final.mod
	$(COPY) $(subst /,\\,$+) $(subst /,\\,$@)

./build/music_07.bin: ./data/music2/dlz-sajt.mod
	$(COPY) $(subst /,\\,$+) $(subst /,\\,$@)

./build/music_08.bin: ./data/music2/virgil-holodash.mod
	$(COPY) $(subst /,\\,$+) $(subst /,\\,$@)

./build/music_09.bin: ./data/music2/squid_ring.mod
	$(COPY) $(subst /,\\,$+) $(subst /,\\,$@)

./build/music_10.bin: ./data/music2/punnik-Lies.mod
	$(COPY) $(subst /,\\,$+) $(subst /,\\,$@)

./build/music_splash.bin: ./data/music2/raven-mono.mod
	$(COPY) $(subst /,\\,$+) $(subst /,\\,$@)

##########################################################################
##########################################################################

./build/!run.txt: ./data/text/!run.txt
	$(DOS2UNIX) -n $< $@

./build/django01.txt: ./data/text/django01.nfo
	$(DOS2UNIX) -n $< $@

##########################################################################
##########################################################################

# Rule to convert PNG files, assumes MODE 9.
%.bin : %.png $(PNG2ARC_DEPS)
	$(PYTHON2) $(PNG2ARC) -o $@ -p $@.pal $< 9

# Rule to LZ4 compress bin files.
%.lz4 : %.bin
	$(LZ4) --best -f $< $@

# Rule to copy MOD files.
%.bin : %.mod
	$(COPY) $(subst /,\\,$+) $(subst /,\\,$@)

##########################################################################
##########################################################################
