#!/bin/bash

# This script downlaods and builds the Mac, iOS and tvOS libcurl libraries with Bitcode enabled

# Credits:
#
# Felix Schwarz, IOSPIRIT GmbH, @@felix_schwarz.
#   https://gist.github.com/c61c0f7d9ab60f53ebb0.git
# Bochun Bai
#   https://github.com/sinofool/build-libcurl-ios
# Jason Cox, @jasonacox
#   https://github.com/jasonacox/Build-OpenSSL-cURL 
# Preston Jennings
#   https://github.com/prestonj/Build-OpenSSL-cURL 

set -e

#set -o xtrace

TOOLS_ROOT=`pwd`
#export ANDROID_NDK="/Users/arun/workspace/ndk/android-ndk-r15c"
export ANDROID_NDK="/Users/arun/workspace/ndk/android-ndk-r17"
ANDROID_API=${ANDROID_API:-23}
ARCHS=("android" "android-armeabi" "android64-aarch64" "android-x86" "android64" "android-mips" "android-mips64")
ABIS=("armeabi" "armeabi-v7a" "arm64-v8a" "x86" "x86_64" "mips" "mips64")
NDK=${ANDROID_NDK}

# set trap to help debug any build errors
trap 'echo "** ERROR with Build - Check /tmp/curl*.log"; tail /tmp/curl*.log' INT TERM EXIT

usage ()
{
	echo "usage: $0 -v 7.50.1"
	trap - INT TERM EXIT
	exit 127
}

VER_NUMBER=""
verbose=1

while getopts "h?v:a:q" opt; do
    case "$opt" in
    h|\?)
        usage
        ;;
	v)	VER_NUMBER=$OPTARG
		;;
	a)	TARGET_ARCH=$OPTARG
		;;
    q)  verbose=0
        ;;
    esac
done

if [ "$verbose" == 1 ]; then
	set -o xtrace
fi

if [ "$VER_NUMBER" == "" ]; then
	CURL_VERSION="curl-7.50.1"
else
	CURL_VERSION="curl-$VER_NUMBER"
fi

OPENSSL="${PWD}/../openssl/Android"

# HTTP2 support
NOHTTP2="/tmp/no-http2"
if [ ! -f "$NOHTTP2" ]; then
	# nghttp2 will be in ../nghttp2/{Platform}/{arch}
	NGHTTP2="${PWD}/../nghttp2"  
fi

if [ ! -z "$NGHTTP2" ]; then 
	echo "Building with HTTP2 Support (nghttp2)"
else
	echo "Building without HTTP2 Support (nghttp2)"
	NGHTTP2CFG=""
	NGHTTP2LIB=""
fi

configureAndroid()
{
	ARCH=$1; ABI=$2; CLANG=${3:-""};
	TOOLS_ROOT="/tmp/curl-Android-${ABI}"
	TOOLCHAIN_ROOT=${TOOLS_ROOT}/${ABI}-android-toolchain
	#TOOLCHAIN_ROOT=/tmp/openssl-android-toolchain

	export PKG_CONFIG_PATH="/tmp/openssl-Android-${ABI}/lib/pkgconfig"


	if [ "$ARCH" == "android" ]; then
		export ARCH_FLAGS="-mthumb"
		export ARCH_LINK=""
		export TOOL="arm-linux-androideabi"
		NDK_FLAGS="--arch=arm"
		export SYSTEM="android"
		export MACHINE=armv7
	elif [ "$ARCH" == "android-armeabi" ]; then
		export ARCH_FLAGS="-march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16 -mthumb -mfpu=neon"
		export ARCH_LINK="-march=armv7-a -Wl,--fix-cortex-a8"
		export TOOL="arm-linux-androideabi"
		NDK_FLAGS="--arch=arm"
		export SYSTEM="android"
		export MACHINE=armv7
	elif [ "$ARCH" == "android64-aarch64" ]; then
		export ARCH_FLAGS=""
		export ARCH_LINK=""
		export TOOL="aarch64-linux-android"
		NDK_FLAGS="--arch=arm64"
		export SYSTEM="android"
		export MACHINE=aarch64
	elif [ "$ARCH" == "android-x86" ]; then
		export ARCH_FLAGS="-march=i686 -mtune=intel -msse3 -mfpmath=sse -m32"
		export ARCH_LINK=""
		export TOOL="i686-linux-android"
		NDK_FLAGS="--arch=x86"
	elif [ "$ARCH" == "android64" ]; then
		export ARCH_FLAGS="-march=x86-64 -msse4.2 -mpopcnt -m64 -mtune=intel"
		export ARCH_LINK=""
		export TOOL="x86_64-linux-android"
		NDK_FLAGS="--arch=x86_64"
		export MACHINE=i686
		export SYSTEM="android"
	#elif [ "$ARCH" == "android-mips" ]; then
		#export ARCH_FLAGS=""
		#export ARCH_LINK=""
		#export TOOL="mipsel-linux-android"
		#NDK_FLAGS="--arch=mips"
	#elif [ "$ARCH" == "android-mips64" ]; then
		#export ARCH="linux64-mips64"
		#export ARCH_FLAGS=""
		#export ARCH_LINK=""
		#export TOOL="mips64el-linux-android"
		#NDK_FLAGS="--arch=mips64"
	fi;


	[ -d ${TOOLCHAIN_ROOT} ] || python $NDK/build/tools/make_standalone_toolchain.py \
                                     --api ${ANDROID_API} \
                                     --stl libc++ \
                                     --install-dir=${TOOLCHAIN_ROOT} \
                                     $NDK_FLAGS

	export TOOLCHAIN_PATH=${TOOLCHAIN_ROOT}/bin
	export NDK_TOOLCHAIN_BASENAME=${TOOLCHAIN_PATH}/${TOOL}
	export SYSROOT=${TOOLCHAIN_ROOT}/sysroot
	export ANDROID_DEV="${SYSROOT}/usr"
	export ANDROID_DEP_FLAGS="${TOOLCHAIN_ROOT}/lib/gcc/${TOOL}/4.9.x/include"
	export CROSS_SYSROOT=$SYSROOT
	if [ -z "${CLANG}" ]; then
		export CC=${NDK_TOOLCHAIN_BASENAME}-gcc
		export CXX=${NDK_TOOLCHAIN_BASENAME}-g++
	else
		export CC=${NDK_TOOLCHAIN_BASENAME}-clang
		export CXX=${NDK_TOOLCHAIN_BASENAME}-clang++
	fi;
	export LINK=${CXX}
	export LD=${NDK_TOOLCHAIN_BASENAME}-ld
	export AR=${NDK_TOOLCHAIN_BASENAME}-ar
	export RANLIB=${NDK_TOOLCHAIN_BASENAME}-ranlib
	export STRIP=${NDK_TOOLCHAIN_BASENAME}-strip
	export CPPFLAGS=${CPPFLAGS:-""}
	export LIBS=${LIBS:-""}
	#export CFLAGS="${ARCH_FLAGS} -fpic -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64 -D__ANDROID_API__=${ANDROID_API}"
	export CFLAGS="${ARCH_FLAGS} -fpic -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64 -I${ANDROID_DEV} -I${ANDROID_DEP_FLAGS}"
	export CXXFLAGS="${CFLAGS} -std=c++11 -frtti -fexceptions -D__ANDROID_API__=${ANDROID_API}"
	export LDFLAGS="${ARCH_LINK}"
	echo "**********************************************"
	echo "use ANDROID_API=${ANDROID_API}"
	echo "use NDK=${NDK}"
	echo "export ARCH=${ARCH}"
	echo "export NDK_TOOLCHAIN_BASENAME=${NDK_TOOLCHAIN_BASENAME}"
	echo "export SYSROOT=${SYSROOT}"
	echo "export CC=${CC}"
	echo "export CXX=${CXX}"
	echo "export LINK=${LINK}"
	echo "export LD=${LD}"
	echo "export AR=${AR}"
	echo "export RANLIB=${RANLIB}"
	echo "export STRIP=${STRIP}"
	echo "export CPPFLAGS=${CPPFLAGS}"
	echo "export CFLAGS=${CFLAGS}"
	echo "export CXXFLAGS=${CXXFLAGS}"
	echo "export LDFLAGS=${LDFLAGS}"
	echo "export LIBS=${LIBS}"
	echo "**********************************************"
}

buildAndroid()
{
	ARCH=$1; ABI=$2;

	pushd . > /dev/null
	cd "${CURL_VERSION}"

	## https://github.com/n8fr8/orbot/issues/92 - OpenSSL doesn't support compilation with clang (on Android) yet. You'll have to use GCC
	#configureAndroid $ARCH $ABI "clang"
	configureAndroid $ARCH $ABI

	# Copy the correct SSL libs
	cp ${OPENSSL}/openssl-${ABI}/lib/libssl.a ${SYSROOT}/usr/lib
	cp ${OPENSSL}/openssl-${ABI}/lib/libcrypto.a ${SYSROOT}/usr/lib
	cp -r ${OPENSSL}/openssl-${ABI}/include/openssl ${SYSROOT}/usr/include

	#if [ ! -z "$NGHTTP2" ]; then 
		#NGHTTP2CFG="--with-nghttp2=${NGHTTP2}/Mac/${ARCH}"
		#NGHTTP2LIB="-L${NGHTTP2}/Mac/${ARCH}/lib"
	#fi
	# export add to LDFLAGS="${NGHTTP2LIB}"

	
	./configure --host=${TOOL} \
			--target=${TOOL} \
			--prefix="/tmp/curl-Android-${ABI}" \
			  --with-random=/dev/urandom \
			  --with-sysroot=${SYSROOT} \
              --with-ssl \
              --enable-ipv6 \
              --enable-static \
              --enable-threaded-resolver \
              --disable-dict \
              --disable-gopher \
              --disable-ldap --disable-ldaps \
              --disable-manual \
              --disable-pop3 --disable-smtp --disable-imap \
              --disable-rtsp \
              --disable-shared \
              --disable-smb \
              --disable-telnet \
			  &> "/tmp/${CURL_VERSION}-Android-${ABI}.log"

	export LIBS="-lssl -lcrypto"
	export LDFLAGS="-arch ${ARCH} -isysroot ${SYSROOT} -L${OPENSSL}/openssl-${ABI}/lib"

	PATH=$TOOLCHAIN_PATH:$PATH

	make clean >> "/tmp/${CURL_VERSION}-Android-${ABI}.log" 2>&1

	if make -j4 >> "/tmp/${CURL_VERSION}-Android-${ABI}.log" 2>&1; then
		make install >> "/tmp/${CURL_VERSION}-Android-${ABI}.log" 2>&1
		
		make clean >> "/tmp/${CURL_VERSION}-Android-${ABI}.log" 2>&1
	fi

	popd > /dev/null


	OUTPUT_ROOT=Android/curl-${ABI}
	[ -d ${OUTPUT_ROOT}/include ] || mkdir -p ${OUTPUT_ROOT}/include

	cp -r "/tmp/curl-Android-${ABI}/include/curl" ${OUTPUT_ROOT}/include

	[ -d ${OUTPUT_ROOT}/lib ] || mkdir -p ${OUTPUT_ROOT}/lib
	cp "/tmp/curl-Android-${ABI}/lib/libcurl.a" ${OUTPUT_ROOT}/lib

}

buildAndroidLibsOnly()
{
	#mkdir -p Android/lib
	#mkdir -p Android/include/openssl/


	#ARCHS=("android" "android-armeabi" "android64-aarch64" "android-x86" "android64" "android-mips" "android-mips64")
	#ABIS=("armeabi" "armeabi-v7a" "arm64-v8a" "x86" "x86_64" "mips" "mips64")

	echo "Building Android libraries"
	#buildAndroid "android" "armeabi"
	buildAndroid "android-armeabi" "armeabi-v7a"
	#buildAndroid "android64-aarch64" "arm64-v8a"
	#buildAndroid "android-x86" "x86"
	#buildAndroid "android64" "x86_64"
	
	#buildAndroid "android-mips" "mips"
	#buildAndroid "android-mips64" "mips64"
}

echo "Cleaning up"
rm -rf include/curl/* lib/*

#mkdir -p lib
#mkdir -p include/curl/

rm -rf "/tmp/${CURL_VERSION}-*"
rm -rf "/tmp/${CURL_VERSION}-*.log"

rm -rf "${CURL_VERSION}"

if [ ! -e ${CURL_VERSION}.tar.gz ]; then
	echo "Downloading ${CURL_VERSION}.tar.gz"
	curl -LO https://curl.haxx.se/download/${CURL_VERSION}.tar.gz
else
	echo "Using ${CURL_VERSION}.tar.gz"
fi

echo "Unpacking curl"
tar xfz "${CURL_VERSION}.tar.gz"

buildAndroidLibsOnly

exit

echo "Cleaning up"
rm -rf /tmp/${CURL_VERSION}-*
rm -rf ${CURL_VERSION}
echo "Checking libraries"
#xcrun -sdk iphoneos lipo -info lib/*.a

#reset trap
trap - INT TERM EXIT

echo "Done"
