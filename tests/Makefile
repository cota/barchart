TESTS := accent
TESTS += accent_column
TESTS += accent_multi
TESTS += cluster_colorset
TESTS += cluster_colorset_patterns
TESTS += cluster15
TESTS += cluster15_patterns
TESTS += cluster_stacked
TESTS += cluster_stacked_colorset
TESTS += cluster_stacked_noglabel
TESTS += errorbars
TESTS += logscale
TESTS += mix3
TESTS += one_dataset_colorset
TESTS += stacked_100
TESTS += stacked_100_patterns

TESTS_DIFF := $(addsuffix .diff,$(TESTS))
TESTS_PNG  := $(addsuffix .png,$(TESTS))
TESTS_SVG  := $(addsuffix .svg,$(TESTS))

ifndef V
	QUIET_DIFF      = @echo '   ' DIFF $@;
	QUIET_PLOT      = @echo '   ' PLOT $@;
	QUIET_BARCHART  = @echo '   ' BARCHART $@;
endif

all: test

test: $(TESTS_DIFF)
.PHONY: test

png: $(TESTS_PNG)
.PHONY: png

svg: $(TESTS_SVG)
.PHONY: svg

GALLERY1_ARGS := --extra-gnuplot='set term pngcairo size 1200,500' \\n \
	--extra-gnuplot='set key inside left top vertical samplen 1 reverse Left' \\n \
	--extra='intra_space_mul=2'
gallery1.png: errorbars.bar
	$(QUIET_BARCHART)../barchart.pl $< \
		$(GALLERY1_ARGS) \
		--extra="title=./barchart.pl tests/$< $(GALLERY1_ARGS)" > $@.plt.tmp
	mv $@.plt.tmp $@.plt
	gnuplot $@.plt > $@

GALLERY2_ARGS := --extra-gnuplot='set term pngcairo size 680,600; set key horizontal samplen 2' \
	\\n --extra='colorset=\#e31a1c,\#fd8d3c,\#fecc5c,\#ffffb2' --extra='max=90'
gallery2.png: cluster_stacked.bar
	$(QUIET_BARCHART)../barchart.pl $< \
		$(GALLERY2_ARGS) \
		--extra="title=./barchart.pl tests/$< \\n $(GALLERY2_ARGS)" > $@.plt.tmp
	mv $@.plt.tmp $@.plt
	gnuplot $@.plt > $@

GALLERY3_ARGS := --extra-gnuplot='set term pngcairo size 1400,800' \
	\\n --extra='colorset=\#352a87,\#0f5cdd,\#1481d6,\#06a4ca,\#2eb7a4,\#87bf77,\#d1bb59,\#fec832,\#d95319'
gallery3.png: stacked_100_patterns.bar
	$(QUIET_BARCHART)../barchart.pl $< \
		$(GALLERY3_ARGS) \
		--extra="title=./barchart.pl tests/$< \\n $(GALLERY3_ARGS)" > $@.plt.tmp
	mv $@.plt.tmp $@.plt
	gnuplot $@.plt > $@

gallery: gallery1.png gallery2.png gallery3.png
.PHONY: gallery

.PRECIOUS: %.plt %.txt

%.diff: %.txt %.gold
	$(QUIET_DIFF)diff $^

%.txt: %.plt
	$(QUIET_PLOT)gnuplot -e 'set term dumb 120 30' $< > $@.tmp && mv $@.tmp $@

%.png: %.plt
	$(QUIET_PLOT)gnuplot -e 'set term pngcairo size 1200,400' $< > $@.tmp && mv $@.tmp $@

%.svg: %.plt
	$(QUIET_PLOT)gnuplot -e 'set term svg enhanced size 1200,400' $< > $@.tmp && mv $@.tmp $@

%.plt: %.bar
	$(QUIET_BARCHART)../barchart.pl $< > $@.tmp && mv $@.tmp $@

clean:
	$(RM) *.txt *.tmp *.plt *.png *.svg
.PHONY: clean
