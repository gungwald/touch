# Requirements:
#
#    GNU make
#        - To execute this make file
#
#    cc65 (ca65 and ld65)
#        - To assemble and link the source code
#          https://cc65.github.io/   (Fedora: dnf install cc65)
#
#    Java and AppleCommander (included)
#        - To create the Apple II disk image
#
#    Python 3
#        - To clear the creation date of NO.CREATE.DATE on the disk
#          (with test/prodos_dates.py)
#
#    LinApple
#        - To load the disk and test the program
#          https://github.com/linappleii/linapple
#          linapple.conf puts a ThunderClock compatible clock card in
#          slot 4 so that ProDOS can read the date and time.
#
CA65=ca65
LD65=ld65
AC=java -jar AppleCommander-ac-1.4.0.jar
LINAPPLE=linapple
PGM=touch
SRC=$(PGM).s
CFG=$(PGM).cfg
BASE_DSK=prodos-2.4.3-boot.dsk
DSK=$(PGM).dsk
VOL=TOUCH

all: $(DSK)

# Copy an existing boot disk so the boot blocks are in place, name the
# volume /TOUCH, then add the program and small text files to try it on.
# NO.CREATE.DATE has its creation date cleared, to try setting one.
# ONLINE, from https://github.com/gungwald/online v1.0.2, is included for
# the user to run if they want to (-ONLINE lists the online volumes).
$(DSK): $(PGM) $(BASE_DSK) test/prodos_dates.py extras/ONLINE
	cp $(BASE_DSK) $(DSK)
	$(AC) -n $(DSK) $(VOL)
	$(AC) -p $(DSK) TOUCH BIN 0x2000 < $(PGM)
	printf 'HELLO\r' | $(AC) -p $(DSK) SAMPLE TXT
	printf 'THIS FILE HAS NO CREATION DATE\r' | \
	    $(AC) -p $(DSK) NO.CREATE.DATE TXT
	python3 test/prodos_dates.py $(DSK) NO.CREATE.DATE create none
	$(AC) -p $(DSK) ONLINE BIN 0x2000 < extras/ONLINE

$(PGM): $(PGM).o $(CFG)
	$(LD65) -C $(CFG) -m $(PGM).map -o $@ $(PGM).o

$(PGM).o: $(SRC)
	$(CA65) -l $(PGM).lst -o $@ $(SRC)

# Show the files on the disk, with their modification dates
cat: $(DSK)
	$(AC) -ll $(DSK)

test: $(DSK)
	$(LINAPPLE) -c linapple.conf --autoboot --d1 $(DSK)

clean:
	$(RM) $(PGM) $(PGM).o $(PGM).lst $(PGM).map $(DSK)

.PHONY: all cat test clean
