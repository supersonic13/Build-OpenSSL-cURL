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

set -o xtrace

# set trap to help debug build errors
trap 'echo "** ERROR with Build - Check /tmp/openssl*.log"; tail /tmp/openssl*.log' INT TERM EXIT

usage ()
{
	echo "usage: $0 [openssl version] [iOS SDK version (defaults to latest)] [tvOS SDK version (defaults to latest)]"
	trap - INT TERM EXIT
	exit 127
}

if [ "$1" == "-h" ]; then
	usage
fi

if [ -z $2 ]; then
	IOS_SDK_VERSION="" #"9.1"
	IOS_MIN_SDK_VERSION="9.0"
	
	TVOS_SDK_VERSION="" #"9.0"
	TVOS_MIN_SDK_VERSION="9.0"
else
	IOS_SDK_VERSION=$2
	TVOS_SDK_VERSION=$3
fi

if [ -z $1 ]; then
	OPENSSL_VERSION="openssl-1.0.1t"
else
	OPENSSL_VERSION="openssl-$1"
fi

DEVELOPER=`xcode-select -print-path`

buildMac()
{
	ARCH=$1

	echo "Building ${OPENSSL_VERSION} for ${ARCH}"

	TARGET="darwin-i386-cc"

	if [[ $ARCH == "x86_64" ]]; then
		TARGET="darwin64-x86_64-cc"
	fi

	#export CC="${BUILD_TOOLS}/usr/bin/clang -fembed-bitcode"
	export CC="${BUILD_TOOLS}/usr/bin/clang "

	pushd . > /dev/null
	cd "${OPENSSL_VERSION}"
	./Configure no-asm ${TARGET} --prefix="/tmp/${OPENSSL_VERSION}-${ARCH}" &> "/tmp/${OPENSSL_VERSION}-${ARCH}.log"
	make >> "/tmp/${OPENSSL_VERSION}-${ARCH}.log" 2>&1
	make install_sw >> "/tmp/${OPENSSL_VERSION}-${ARCH}.log" 2>&1
	# Keep openssl binary for Mac version
	cp "/tmp/${OPENSSL_VERSION}-${ARCH}/bin/openssl" "/tmp/openssl"
	make clean >> "/tmp/${OPENSSL_VERSION}-${ARCH}.log" 2>&1
	popd > /dev/null
}

buildIOS()
{
	ARCH=$1

	pushd . > /dev/null
	cd "${OPENSSL_VERSION}"
  
	if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
		PLATFORM="iPhoneSimulator"
	else
		PLATFORM="iPhoneOS"
		sed -ie "s!static volatile sig_atomic_t intr_signal;!static volatile intr_signal;!" "crypto/ui/ui_openssl.c"
	fi
  
	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${IOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	#export CC="${BUILD_TOOLS}/usr/bin/gcc -fembed-bitcode -arch ${ARCH}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc -arch ${ARCH}"
   
	echo "Building ${OPENSSL_VERSION} for ${PLATFORM} ${IOS_SDK_VERSION} ${ARCH}"

	if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
		./Configure no-asm darwin64-x86_64-cc --prefix="/tmp/${OPENSSL_VERSION}-iOS-${ARCH}" &> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log"
	else
		./Configure iphoneos-cross --prefix="/tmp/${OPENSSL_VERSION}-iOS-${ARCH}" &> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log"
	fi
	# add -isysroot to CC=
	sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=${IOS_MIN_SDK_VERSION} !" "Makefile"

	make >> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log" 2>&1
	make install_sw >> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log" 2>&1
	make clean >> "/tmp/${OPENSSL_VERSION}-iOS-${ARCH}.log" 2>&1
	popd > /dev/null
}

buildTVOS()
{
	ARCH=$1

	pushd . > /dev/null
	cd "${OPENSSL_VERSION}"
  
	if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
		PLATFORM="AppleTVSimulator"
	else
		PLATFORM="AppleTVOS"
		sed -ie "s!static volatile sig_atomic_t intr_signal;!static volatile intr_signal;!" "crypto/ui/ui_openssl.c"
		#sed -ie "s!setcontext(&n->fibre);!static volatile intr_signal;!" "crypto/ui/ui_openssl.c"
	fi
  
	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${TVOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	#export CC="${BUILD_TOOLS}/usr/bin/gcc -fembed-bitcode -arch ${ARCH}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc -arch ${ARCH}"
   #	-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -mtvos-version-min=${TVOS_MIN_SDK_VERSION}"
	export LC_CTYPE=C
   
	echo "Building ${OPENSSL_VERSION} for ${PLATFORM} ${TVOS_SDK_VERSION} ${ARCH}"

	# Patch apps/speed.c to not use fork() since it's not available on tvOS
	LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "./apps/speed.c"

	# Patch Configure to build for tvOS, not iOS
	LANG=C sed -i -- 's/D\_REENTRANT\:iOS/D\_REENTRANT\:tvOS/' "./Configure"
	chmod u+x ./Configure

	if [[ "${ARCH}" == "x86_64" ]]; then
		./Configure no-asm darwin64-x86_64-cc --prefix="/tmp/${OPENSSL_VERSION}-tvOS-${ARCH}" &> "/tmp/${OPENSSL_VERSION}-tvOS-${ARCH}.log"
	else
		#./Configure iphoneos-cross --prefix="/tmp/${OPENSSL_VERSION}-tvOS-${ARCH}" &> "/tmp/${OPENSSL_VERSION}-tvOS-${ARCH}.log"
		./Configure iphoneos-cross --prefix="/tmp/${OPENSSL_VERSION}-tvOS-${ARCH}" &> "/tmp/${OPENSSL_VERSION}-tvOS-${ARCH}.log"
	fi
	# add -isysroot to CC=
	#sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -mtvos-version-min=${TVOS_MIN_SDK_VERSION} !" "Makefile"
	#sed -ie "s!^CFLAGS=!CFLAGS=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -mtvos-version-min=${TVOS_MIN_SDK_VERSION} !" "Makefile"
	#sed -ie "s!-mios-version-min=7.0.0! !" "Makefile"
	sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -mtvos-version-min=${TVOS_MIN_SDK_VERSION} !" "Makefile"

	make >> "/tmp/${OPENSSL_VERSION}-tvOS-${ARCH}.log" 2>&1
	make install_sw >> "/tmp/${OPENSSL_VERSION}-tvOS-${ARCH}.log" 2>&1
	make clean >> "/tmp/${OPENSSL_VERSION}-tvOS-${ARCH}.log" 2>&1
	popd > /dev/null
}


echo "Cleaning up"
rm -rf include/openssl/* lib/*

buildMacLibsOnly()
{
mkdir -p Mac/lib
mkdir -p Mac/include/openssl/

echo "Building Mac libraries"
buildMac "x86_64"

echo "Copying headers"
cp /tmp/${OPENSSL_VERSION}-x86_64/include/openssl/* Mac/include/openssl/

lipo "/tmp/${OPENSSL_VERSION}-x86_64/lib/libcrypto.a" -create -output Mac/lib/libcrypto.a

lipo "/tmp/${OPENSSL_VERSION}-x86_64/lib/libssl.a" -create -output Mac/lib/libssl.a
}

buildIOSLibsOnly()
{
	mkdir -p iOS/lib
	mkdir -p iOS/include/openssl/
	echo "Building iOS libraries"
buildIOS "armv7"
buildIOS "armv7s"
buildIOS "arm64"
buildIOS "x86_64"
#buildIOS "i386"

#cp /tmp/${OPENSSL_VERSION}-x86_64/include/openssl/* iOS/include/openssl/
cp /tmp/${OPENSSL_VERSION}-iOS-armv7/include/openssl/* iOS/include/openssl/

lipo \
	"/tmp/${OPENSSL_VERSION}-iOS-armv7/lib/libcrypto.a" \
	"/tmp/${OPENSSL_VERSION}-iOS-armv7s/lib/libcrypto.a" \
	"/tmp/${OPENSSL_VERSION}-iOS-arm64/lib/libcrypto.a" \
	"/tmp/${OPENSSL_VERSION}-iOS-x86_64/lib/libcrypto.a" \
	-create -output iOS/lib/libcrypto.a
	
#"/tmp/${OPENSSL_VERSION}-iOS-i386/lib/libcrypto.a" \

lipo \
	"/tmp/${OPENSSL_VERSION}-iOS-armv7/lib/libssl.a" \
	"/tmp/${OPENSSL_VERSION}-iOS-armv7s/lib/libssl.a" \
	"/tmp/${OPENSSL_VERSION}-iOS-arm64/lib/libssl.a" \
	"/tmp/${OPENSSL_VERSION}-iOS-x86_64/lib/libssl.a" \
	-create -output iOS/lib/libssl.a
	
#"/tmp/${OPENSSL_VERSION}-iOS-i386/lib/libssl.a" \

}

buildTVOSLibsOnly()
{
mkdir -p tvOS/lib
mkdir -p tvOS/include/openssl/
	echo "Building tvOS libraries"
buildTVOS "arm64"
buildTVOS "x86_64"

cp /tmp/${OPENSSL_VERSION}-tvOS-arm64/include/openssl/* tvOS/include/openssl/

lipo \
	"/tmp/${OPENSSL_VERSION}-tvOS-arm64/lib/libcrypto.a" \
	"/tmp/${OPENSSL_VERSION}-tvOS-x86_64/lib/libcrypto.a" \
	-create -output tvOS/lib/libcrypto.a

lipo \
	"/tmp/${OPENSSL_VERSION}-tvOS-arm64/lib/libssl.a" \
	"/tmp/${OPENSSL_VERSION}-tvOS-x86_64/lib/libssl.a" \
	-create -output tvOS/lib/libssl.a


}


rm -rf "/tmp/${OPENSSL_VERSION}-*"
rm -rf "/tmp/${OPENSSL_VERSION}-*.log"

rm -rf "${OPENSSL_VERSION}"

if [ ! -e ${OPENSSL_VERSION}.tar.gz ]; then
	echo "Downloading ${OPENSSL_VERSION}.tar.gz"
	curl -LO https://www.openssl.org/source/${OPENSSL_VERSION}.tar.gz
else
	echo "Using ${OPENSSL_VERSION}.tar.gz"
fi

echo "Unpacking openssl"
tar xfz "${OPENSSL_VERSION}.tar.gz"

buildMacLibsOnly

buildIOSLibsOnly

buildTVOSLibsOnly

echo "Cleaning up"
rm -rf /tmp/${OPENSSL_VERSION}-*
rm -rf ${OPENSSL_VERSION}

echo "Checking OPENSSL Apple libraries"
xcrun -sdk iphoneos lipo -info Mac/lib/*.a
xcrun -sdk iphoneos lipo -info iOS/lib/*.a
xcrun -sdk iphoneos lipo -info tvOS/lib/*.a

#reset trap
trap - INT TERM EXIT

echo "Done"
