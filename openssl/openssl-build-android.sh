#!/bin/bash

# This script downlaods and builds the Mac, iOS and tvOS openSSL libraries with Bitcode enabled

# Credits:
#
# Stefan Arentz
#   https://github.com/st3fan/ios-openssl
# Felix Schulze
#   https://github.com/x2on/OpenSSL-for-iPhone/blob/master/build-libssl.sh
# James Moore
#   https://gist.github.com/foozmeat/5154962
# Peter Steinberger, PSPDFKit GmbH, @steipete.
#   https://gist.github.com/felix-schwarz/c61c0f7d9ab60f53ebb0
# Jason Cox, @jasonacox
#   https://github.com/jasonacox/Build-OpenSSL-cURL

set -e

#set -o xtrace

TOOLS_ROOT=`pwd`
#export ANDROID_NDK="/Users/arun/workspace/ndk/android-ndk-r15c"
#export ANDROID_NDK="/Users/arun/workspace/ndk/android-ndk-r14b"
export ANDROID_NDK="/Users/arun/workspace/ndk/android-ndk-r16b"
ANDROID_API=${ANDROID_API:-21}
ARCHS=("android" "android-armeabi" "android64-aarch64" "android-x86" "android64" "android-mips" "android-mips64")
ABIS=("armeabi" "armeabi-v7a" "arm64-v8a" "x86" "x86_64" "mips" "mips64")
NDK=${ANDROID_NDK}
#MAKE_EXE=${ANDROID_NDK}/prebuilt/darwin-x86_64/bin/make
MAKE_EXE=make

# set trap to help debug build errors
trap 'echo "** ERROR with Build - Check /tmp/openssl*.log"; tail /tmp/openssl*.log' INT TERM EXIT

usage ()
{
	echo "usage: $0 -v 1.0.2o"
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
else
	QUIET_DEBUG="-q"
fi

if [ "$VER_NUMBER" == "" ]; then
	OPENSSL_VERSION="openssl-1.0.1t"
else
	OPENSSL_VERSION="openssl-$VER_NUMBER"
fi

configureAndroid()
{
	ARCH=$1; ABI=$2; CLANG=${3:-""};
	TOOLS_ROOT="/tmp/openssl-Android-${ABI}"
	TOOLCHAIN_ROOT=${TOOLS_ROOT}/${ABI}-android-toolchain

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

                                 #--stl libc++ \
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
	#export CROSS_COMPILE="${NDK_TOOLCHAIN_BASENAME}"
	export LINK=${CXX}
	export LD=${NDK_TOOLCHAIN_BASENAME}-ld
	export AR=${NDK_TOOLCHAIN_BASENAME}-ar
	export RANLIB=${NDK_TOOLCHAIN_BASENAME}-ranlib
	export STRIP=${NDK_TOOLCHAIN_BASENAME}-strip
	export CPPFLAGS=${CPPFLAGS:-""}
	export LIBS=${LIBS:-""}
	#export CFLAGS="${ARCH_FLAGS} -fpic -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64 -D__ANDROID_API__=${ANDROID_API}"
	export CFLAGS="${ARCH_FLAGS} -fpic -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64"
	export CXXFLAGS="${CFLAGS} -std=c++11 -frtti -fexceptions"
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
	cd "${OPENSSL_VERSION}"

	## https://github.com/n8fr8/orbot/issues/92 - OpenSSL doesn't support compilation with clang (on Android) yet. You'll have to use GCC
	#configureAndroid $ARCH $ABI "clang"
	configureAndroid $ARCH $ABI "clang" 

	if [[ $OPENSSL_VERSION != openssl-1.1.* ]]; then
		if [[ $ARCH == "android-armeabi" ]]; then
			ARCH="android-armv7"
		elif [[ $ARCH == "android64" ]]; then 
			#ARCH="linux-x86_64 shared no-ssl2 no-ssl3 no-hw "
			ARCH="linux-x86_64 no-ssl2 no-ssl3 no-hw "
		elif [[ "$ARCH" == "android64-aarch64" ]]; then
			#ARCH="android shared no-ssl2 no-ssl3 no-hw "
			ARCH="android no-ssl2 no-ssl3 no-hw "
		fi
	fi

	echo "Building ${OPENSSL_VERSION} for Android ${ARCH}"

	#./Configure $ARCH \
			  #--prefix="/tmp/${OPENSSL_VERSION}-Android-${ABI}" \
			  #--openssldir="/tmp/${OPENSSL_VERSION}-Android-${ABI}" \
              #--with-zlib-include=$SYSROOT/usr/include \
              #--with-zlib-lib=$SYSROOT/usr/lib \
              #zlib \
              #no-asm \
              #no-shared \
              #no-unit-test	\
			  #&> "/tmp/${OPENSSL_VERSION}-Android-${ABI}.log"

	./Configure $ARCH \
			  --prefix="/tmp/openssl-Android-${ABI}" \
			  --openssldir="/tmp/openssl-Android-${ABI}" \
              --with-zlib-include=$SYSROOT/usr/include \
              --with-zlib-lib=$SYSROOT/usr/lib \
              no-zlib \
              no-asm \
              no-shared \
              no-unit-test	\
			  no-ui \
			  &> "/tmp/${OPENSSL_VERSION}-Android-${ABI}.log"
	PATH=$TOOLCHAIN_PATH:$PATH


	###
	##
	# Fix the makefile.
	perl -pi -e 's/install: all install_docs install_sw/install: install_docs install_sw/g' Makefile
	sed -ie "s!-mandroid!!" "Makefile"
	sed -ie "s!-O3!-Os!" "Makefile"
	#sed -ie "/^DEPFLAG= /s/$/ -I\$(ANDROID_DEP_FLAGS)/" "Makefile"
	sed -ie "/^CFLAG= /s/$/ -I\$(ANDROID_DEP_FLAGS)/" "Makefile"

	#sed -ie "1i #ifdef IGNORE_THIS_FILE" crypto/ui/ui_openssl.c
	#sed -ie "\$a#endif" crypto/ui/ui_openssl.c
	#sed -ie "s/#  define TERMIOS/\/\/#  define TERMIOS/" crypto/ui/ui_openssl.c
	#sed -ie "s/#   define TERMIOS/\/\/#   define TERMIOS/" crypto/ui/ui_openssl.c
	#sed -ie "s/#  define TERMIO/\/\/#  define TERMIO/" crypto/ui/ui_openssl.c


	#$MAKE_EXE clean >> "/tmp/${OPENSSL_VERSION}-Android-${ABI}.log" 2>&1
	#$MAKE_EXE depend >> "/tmp/${OPENSSL_VERSION}-Android-${ABI}.log" 2>&1
	#$MAKE_EXE all >> "/tmp/${OPENSSL_VERSION}-Android-${ABI}.log" 2>&1
	#$MAKE_EXE clean >> "/tmp/${OPENSSL_VERSION}-Android-${ABI}.log" 2>&1

	#$MAKE_EXE depend >> "/tmp/${OPENSSL_VERSION}-Android-${ABI}.log" 2>&1
	#$MAKE_EXE all >> "/tmp/${OPENSSL_VERSION}-Android-${ABI}.log" 2>&1

	$MAKE_EXE depend >> "/tmp/${OPENSSL_VERSION}-Android-${ABI}.log" 2>&1
	$MAKE_EXE all >> "/tmp/${OPENSSL_VERSION}-Android-${ABI}.log" 2>&1
	$MAKE_EXE install_sw >> "/tmp/${OPENSSL_VERSION}-Android-${ABI}.log" 2>&1



	#if $MAKE_EXE -j4 >> "/tmp/${OPENSSL_VERSION}-Android-${ABI}.log" 2>&1; then
		#$MAKE_EXE install_sw >> "/tmp/${OPENSSL_VERSION}-Android-${ABI}.log" 2>&1
		#$MAKE_EXE clean >> "/tmp/${OPENSSL_VERSION}-Android-${ABI}.log" 2>&1
	#fi

	#exit
	popd > /dev/null

	OUTPUT_ROOT=Android/openssl-${ABI}
	[ -d ${OUTPUT_ROOT}/include ] || mkdir -p ${OUTPUT_ROOT}/include

	cp -r "/tmp/openssl-Android-${ABI}/include/openssl" ${OUTPUT_ROOT}/include

	[ -d ${OUTPUT_ROOT}/lib ] || mkdir -p ${OUTPUT_ROOT}/lib
	cp "/tmp/openssl-Android-${ABI}/lib/libcrypto.a" ${OUTPUT_ROOT}/lib
	cp "/tmp/openssl-Android-${ABI}/lib/libssl.a" ${OUTPUT_ROOT}/lib

}

buildAndroidLibsOnly()
{
	mkdir -p Android/lib
	mkdir -p Android/include/openssl/


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
rm -rf include/openssl/* lib/*

rm -rf "/tmp/openssl-*"
rm -rf "/tmp/openssl-*.log"

rm -rf "${OPENSSL_VERSION}"

if [ ! -e ${OPENSSL_VERSION}.tar.gz ]; then
	echo "Downloading ${OPENSSL_VERSION}.tar.gz"
	curl -LO https://www.openssl.org/source/${OPENSSL_VERSION}.tar.gz
else
	echo "Using ${OPENSSL_VERSION}.tar.gz"
fi

echo "Unpacking openssl"
tar xfz "${OPENSSL_VERSION}.tar.gz"

buildAndroidLibsOnly

exit

echo "Cleaning up"
rm -rf /tmp/openssl-*
rm -rf ${OPENSSL_VERSION}

#reset trap
trap - INT TERM EXIT

echo "Done"
