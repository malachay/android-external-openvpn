LOCAL_PATH:= $(call my-dir)

#on a 32bit maschine run ./configure --enable-password-save --disable-pkcs11 --with-ifconfig-path=/system/bin/ifconfig --with-route-path=/system/bin/route
#from generated Makefile copy variable contents of openvpn_SOURCES to common_SRC_FILES
# append missing.c to the end of the list
# missing.c defines undefined functions.
# in tun.c replace /dev/net/tun with /dev/tun

common_SRC_FILES:= \
        base64.c \
        buffer.c  \
        crypto.c  \
        dhcp.c  \
        error.c  \
        event.c  \
        fdmisc.c  \
        forward.c   \
        fragment.c  \
        gremlin.c  \
        helper.c  \
        httpdigest.c  \
        lladdr.c  \
        init.c  \
        interval.c  \
        list.c  \
        lzo.c  \
        manage.c  \
        mbuf.c  \
        misc.c  \
        mroute.c  \
        mss.c  \
        mtcp.c  \
        mtu.c  \
        mudp.c  \
        multi.c  \
        ntlm.c  \
        occ.c   \
        pkcs11.c \
        openvpn.c  \
        options.c  \
        otime.c  \
        packet_id.c  \
        perf.c  \
        pf.c   \
        ping.c   \
        plugin.c  \
        pool.c  \
        proto.c  \
        proxy.c  \
        ieproxy.c \
        ps.c  \
        push.c  \
        reliable.c  \
        route.c  \
        schedule.c  \
        session_id.c  \
        shaper.c  \
        sig.c  \
        socket.c  \
        socks.c  \
        ssl.c  \
        status.c  \
        tun.c  \
        win32.c \
        cryptoapi.c

#common_CFLAGS += -DNO_WINDOWS_BRAINDEATH 

common_C_INCLUDES += \
	$(LOCAL_PATH)/../openssl/ \
	$(LOCAL_PATH)/../openssl/include \
	$(LOCAL_PATH)/../openssl/include/openssl \
	$(LOCAL_PATH)/../openssl/crypto \
	$(LOCAL_PATH)/../openssl/crypto/evp \
	$(LOCAL_PATH)/../openssl/ssl \
	$(LOCAL_PATH)/../liblzo/include \

common_SHARED_LIBRARIES := 

ifneq ($(TARGET_SIMULATOR),true)
	common_SHARED_LIBRARIES += libdl
endif


# static linked binary
# =====================================================

#include $(CLEAR_VARS)
#LOCAL_SRC_FILES:= $(common_SRC_FILES)
#LOCAL_CFLAGS:= $(common_CFLAGS)
#LOCAL_C_INCLUDES:= $(common_C_INCLUDES)

#LOCAL_SHARED_LIBRARIES += $(common_SHARED_LIBRARIES)
#LOCAL_SHARED_LIBRARIES += \
	libcrypto \
	libssl \
	liblzo

#LOCAL_STATIC_LIBRARIES := \
	libcrypto-static \
	libssl-static \
	liblzo-static
#LOCAL_PRELINK_MODULE:= false
#LOCAL_LDFLAGS := -static -static-libgcc
#LOCAL_MODULE:= openvpn-static
#LOCAL_MODULE_PATH := $(TARGET_OUT_OPTIONAL_EXECUTABLES)
#LOCAL_LDLIBS += -L$(SYSROOT)/usr/lib/android.so
#LOCAL_LDLIBS += -L$(SYSROOT)/usr/lib/libdl.so
#include $(BUILD_EXECUTABLE)

# dynamic linked binary
# =====================================================


include $(CLEAR_VARS)
LOCAL_SRC_FILES:= $(common_SRC_FILES)
LOCAL_CFLAGS:= $(common_CFLAGS)
LOCAL_C_INCLUDES:= $(common_C_INCLUDES)

LOCAL_SHARED_LIBRARIES:= $(common_SHARED_LIBRARIES) libssl libcrypto liblzo

#LOCAL_LDLIBS += -ldl
#LOCAL_PRELINK_MODULE:= false

LOCAL_MODULE:= openvpn
LOCAL_MODULE_PATH := $(TARGET_OUT_OPTIONAL_EXECUTABLES)
include $(BUILD_EXECUTABLE)
