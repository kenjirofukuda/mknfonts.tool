include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = mknfonts

PACKAGE_NAME = mknfonts
CVS_MODULE_NAME = mknfonts
CVS_OPTIONS = -d /opt/cvsroot
VERSION = 0.5

ADDITIONAL_OBJCFLAGS += -Wall -O2

ADDITIONAL_INCLUDE_DIRS += `freetype-config --cflags`
ADDITIONAL_LDFLAGS += `freetype-config --libs`

mknfonts_OBJC_FILES = mknfonts.m

include $(GNUSTEP_MAKEFILES)/tool.make

