all:

LC_ALL:=C
LANG:=C
export LC_ALL LANG

empty:=
space:= $(empty) $(empty)

ifneq ($(GLUON_BUILD),1)

override GLUON_BUILD=1
export GLUON_BUILD
TARGETS := all prepare images
SUBMAKE := $(MAKE) --no-print-directory

FORCE: ;

$(TARGETS): FORCE
	@$(SUBMAKE) $@

image/%:: FORCE
	@$(SUBMAKE) $@

clean: FORCE
	@$(SUBMAKE) clean-gluon

cleanall: FORCE
	@$(SUBMAKE) clean

.PHONY: FORCE

else

GLUONMAKE = $(SUBMAKE) -C $(GLUON_OPENWRTDIR) -f $(GLUONDIR)/Makefile

ifneq ($(OPENWRT_BUILD),1)

GLUONDIR:=${CURDIR}

include $(GLUONDIR)/builder/gluon.mk

TOPDIR:=$(GLUON_OPENWRTDIR)
export TOPDIR

include $(TOPDIR)/include/host.mk

_SINGLE=export MAKEFLAGS=$(space);

override OPENWRT_BUILD=1
override REVISION:=$(shell $(GLUON_BUILDERDIR)/openwrt_rev.sh $(GLUONDIR))
GREP_OPTIONS=
export OPENWRT_BUILD GREP_OPTIONS REVISION

include $(TOPDIR)/include/debug.mk
include $(TOPDIR)/include/depends.mk
include $(TOPDIR)/include/toplevel.mk

all: FORCE
	+@$(GLUONMAKE) prepare
	+@$(GLUONMAKE) images

prepare: FORCE
	+@$(GLUONMAKE) prepare

images: FORCE
	+@$(GLUONMAKE) images

image/%:: FORCE
	+@$(GLUONMAKE) $@

clean: clean-gluon

clean-gluon:
	rm -rf $(GLUON_BUILDDIR)

else

include $(GLUONDIR)/builder/gluon.mk

include $(TOPDIR)/include/host.mk

include rules.mk
include $(INCLUDE_DIR)/depends.mk
include $(INCLUDE_DIR)/subdir.mk
include $(INCLUDE_DIR)/kernel.mk

include package/Makefile
include tools/Makefile
include toolchain/Makefile

BOARD := ar71xx
PROFILES :=
PROFILE_PACKAGES :=

gluon_prepared_stamp := $(GLUON_BUILDDIR)/$(BOARD)/prepared

define GluonProfile
image/$(1): $(gluon_prepared_stamp)
	$(MAKE) -C $(GLUON_BUILDERDIR) image \
		PROFILE="$(1)" \
		$(if $(2),PACKAGES="$(2)")

PROFILES += $(1)
PROFILE_PACKAGES += $(filter-out -%,$(2))
endef

include $(GLUONDIR)/profiles.mk

$(BUILD_DIR)/.prepared: Makefile
	@mkdir -p $$(dirname $@)
	@touch $@

$(toolchain/stamp-install): $(tools/stamp-install)
$(package/stamp-compile): $(package/stamp-cleanup)

feeds: FORCE
	ln -sf $(GLUON_BUILDERDIR)/feeds.conf feeds.conf

	scripts/feeds uninstall -a
	scripts/feeds update -a

	scripts/feeds install -a

	rm -f $(TMP_DIR)/info/.files-packageinfo-$(SCAN_COOKIE)
	$(SUBMAKE) prepare-tmpinfo OPENWRT_BUILD=0

config: FORCE
	echo -e 'CONFIG_TARGET_$(BOARD)=y\nCONFIG_TARGET_ROOTFS_JFFS2=n\n$(subst ${space},\n,$(patsubst %,CONFIG_PACKAGE_%=m,$(GLUON_PACKAGES) $(PROFILE_PACKAGES)))' > .config
	$(SUBMAKE) defconfig OPENWRT_BUILD=0

toolchain: $(toolchain/stamp-install) $(tools/stamp-install)

kernel: FORCE
	$(NO_TRACE_MAKE) -C $(TOPDIR)/target/linux/$(BOARD) -f $(GLUON_BUILDERDIR)/Makefile.target $(LINUX_DIR)/.image TARGET_BUILD=1
	$(NO_TRACE_MAKE) -C $(TOPDIR)/target/linux/$(BOARD) -f $(GLUON_BUILDERDIR)/Makefile.target $(LINUX_DIR)/.modules TARGET_BUILD=1

packages: $(package/stamp-compile)
	$(_SINGLE)$(SUBMAKE) -r package/index

prepare-image: FORCE
	rm -rf $(BOARD_KDIR)
	mkdir -p $(BOARD_KDIR)
	cp $(KERNEL_BUILD_DIR)/vmlinux $(KERNEL_BUILD_DIR)/vmlinux.elf $(BOARD_KDIR)/
	$(SUBMAKE) -C $(TOPDIR)/target/linux/$(BOARD)/image -f $(GLUON_BUILDERDIR)/Makefile.image prepare KDIR="$(BOARD_KDIR)"

prepare: FORCE
	mkdir -p $(GLUON_IMAGEDIR) $(GLUON_BUILDDIR)/$(BOARD)
	echo 'src packages file:../openwrt/bin/$(BOARD)/packages' > $(GLUON_BUILDDIR)/$(BOARD)/opkg.conf

	$(GLUONMAKE) feeds
	$(GLUONMAKE) config
	$(GLUONMAKE) toolchain
	$(GLUONMAKE) kernel
	$(GLUONMAKE) packages
	$(GLUONMAKE) prepare-image

	touch $(gluon_prepared_stamp)

$(gluon_prepared_stamp):
	$(GLUONMAKE) prepare

images: $(patsubst %,image/%,$(PROFILES))

.PHONY: all images prepare clean cleanall

endif
endif
