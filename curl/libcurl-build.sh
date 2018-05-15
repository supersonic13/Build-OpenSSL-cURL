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

set -o xtrace

# set trap to help debug any build errors
trap 'echo "** ERROR with Build - Check /tmp/curl*.log"; tail /tmp/curl*.log' INT TERM EXIT

usage ()
{
	echo "usage: $0 [curl version] [iOS SDK version (defaults to latest)] [tvOS SDK version (defaults to latest)]"
	trap - INT TERM EXIT
	exit 127
}

VER_NUMBER=""

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

if [ "$VER_NUMBER" == "" ]; then
	CURL_VERSION="curl-7.54.0"
else
	CURL_VERSION="curl-$VER_NUMBER"
fi


if [ "$1" == "-h" ]; then
	usage
fi

IOS_SDK_VERSION="" #"9.1"
IOS_MIN_SDK_VERSION="9.0"
TVOS_SDK_VERSION="" #"9.0"
TVOS_MIN_SDK_VERSION="9.0"

OPENSSL="${PWD}/../openssl"  
DEVELOPER=`xcode-select -print-path`
IPHONEOS_DEPLOYMENT_TARGET="6.0"

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

buildMac()
{
	ARCH=$1
	HOST="i386-apple-darwin"

	echo "Building ${CURL_VERSION} for ${ARCH}"

	TARGET="darwin-i386-cc"

	if [[ $ARCH == "x86_64" ]]; then
		TARGET="darwin64-x86_64-cc"
	fi

	if [ ! -z "$NGHTTP2" ]; then 
		NGHTTP2CFG="--with-nghttp2=${NGHTTP2}/Mac/${ARCH}"
		NGHTTP2LIB="-L${NGHTTP2}/Mac/${ARCH}/lib"
	fi
	
	export CC="${BUILD_TOOLS}/usr/bin/clang"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -fembed-bitcode"
	export LDFLAGS="-arch ${ARCH} -L${OPENSSL}/Mac/lib ${NGHTTP2LIB}"
	pushd . > /dev/null
	cd "${CURL_VERSION}"
	./configure -prefix="/tmp/${CURL_VERSION}-${ARCH}" -disable-shared --enable-static -with-random=/dev/urandom --with-ssl=${OPENSSL}/Mac ${NGHTTP2CFG} --host=${HOST} \
	          --enable-ipv6 \
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
              --disable-verbose \
			  &> "/tmp/${CURL_VERSION}-${ARCH}.log"

	make -j8 >> "/tmp/${CURL_VERSION}-${ARCH}.log" 2>&1
	make install >> "/tmp/${CURL_VERSION}-${ARCH}.log" 2>&1
	# Save curl binary for Mac Version
	cp "/tmp/${CURL_VERSION}-${ARCH}/bin/curl" "/tmp/curl"
	make clean >> "/tmp/${CURL_VERSION}-${ARCH}.log" 2>&1
	popd > /dev/null
}

buildIOS()
{
	ARCH=$1
	BITCODE=$2

	pushd . > /dev/null
	cd "${CURL_VERSION}"
  
	if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
		PLATFORM="iPhoneSimulator"
	else
		PLATFORM="iPhoneOS"
	fi

	if [[ "${BITCODE}" == "nobitcode" ]]; then
		CC_BITCODE_FLAG=""	
	else
		CC_BITCODE_FLAG="-fembed-bitcode"	
	fi

	if [ ! -z "$NGHTTP2" ]; then 
		NGHTTP2CFG="--with-nghttp2=${NGHTTP2}/iOS/${ARCH}"
		NGHTTP2LIB="-L${NGHTTP2}/iOS/${ARCH}/lib"
	fi
	  
	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${IOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=${IOS_MIN_SDK_VERSION} ${CC_BITCODE_FLAG}"
	export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -L${OPENSSL}/iOS/lib ${NGHTTP2LIB}"
   
	echo "Building ${CURL_VERSION} for ${PLATFORM} ${IOS_SDK_VERSION} ${ARCH} ${BITCODE}"

	if [[ "${ARCH}" == "arm64" ]]; then
		./configure -prefix="/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}" -disable-shared --enable-static -with-random=/dev/urandom --with-ssl=${OPENSSL}/iOS ${NGHTTP2CFG} --host="arm-apple-darwin" \
			--enable-ipv6 \
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
			--disable-verbose \
			&> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log"
	else
		./configure -prefix="/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}" -disable-shared --enable-static -with-random=/dev/urandom --with-ssl=${OPENSSL}/iOS ${NGHTTP2CFG} --host="${ARCH}-apple-darwin" \
			--enable-ipv6 \
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
			--disable-verbose \
			&> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log"
	fi

	make -j8 >> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	make install >> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	make clean >> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	popd > /dev/null
}

buildTVOS()
{
	ARCH=$1

	pushd . > /dev/null
	cd "${CURL_VERSION}"
  
	if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
		PLATFORM="AppleTVSimulator"
	else
		PLATFORM="AppleTVOS"
	fi
	
	if [ ! -z "$NGHTTP2" ]; then 
		NGHTTP2CFG="--with-nghttp2=${NGHTTP2}/tvOS/${ARCH}"
		NGHTTP2LIB="-L${NGHTTP2}/tvOS/${ARCH}/lib"
	fi
  
	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${TVOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -mtvos-version-min=${TVOS_MIN_SDK_VERSION} -fembed-bitcode"
	export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -L${OPENSSL}/tvOS/lib ${NGHTTP2LIB}"
#	export PKG_CONFIG_PATH 
   
	echo "Building ${CURL_VERSION} for ${PLATFORM} ${TVOS_SDK_VERSION} ${ARCH}"

	./configure -prefix="/tmp/${CURL_VERSION}-tvOS-${ARCH}" --host="arm-apple-darwin" -disable-shared -with-random=/dev/urandom --disable-ntlm-wb --with-ssl="${OPENSSL}/tvOS" ${NGHTTP2CFG} \
			--enable-ipv6 \
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
			--disable-verbose \
			&> "/tmp/${CURL_VERSION}-tvOS-${ARCH}.log"

	# Patch to not use fork() since it's not available on tvOS
        LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "./lib/curl_config.h"
        LANG=C sed -i -- 's/HAVE_FORK"]=" 1"/HAVE_FORK\"]=" 0"/' "config.status"

	make -j8 >> "/tmp/${CURL_VERSION}-tvOS-${ARCH}.log" 2>&1
	make install >> "/tmp/${CURL_VERSION}-tvOS-${ARCH}.log" 2>&1
	make clean >> "/tmp/${CURL_VERSION}-tvOS-${ARCH}.log" 2>&1
	popd > /dev/null
}

echo "Cleaning up"
rm -rf include/curl/* lib/*

mkdir -p lib
mkdir -p include/curl/

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

buildMacLibsOnly()
{

mkdir -p Mac/lib
mkdir -p Mac/include/curl/

echo "Building Mac libraries"
buildMac "x86_64"

cp /tmp/${CURL_VERSION}-x86_64/include/curl/* Mac/include/curl/

echo "Copying headers"
cp /tmp/${CURL_VERSION}-x86_64/include/curl/* include/curl/

lipo \
	"/tmp/${CURL_VERSION}-x86_64/lib/libcurl.a" \
	-create -output Mac/lib/libcurl.a
}

buildIOSLibsOnly()
{

mkdir -p iOS/lib
mkdir -p iOS/include/curl/

echo "Building iOS libraries (bitcode)"
buildIOS "armv7" "bitcode"
buildIOS "armv7s" "bitcode"
buildIOS "arm64" "bitcode"
buildIOS "x86_64" "bitcode"
#buildIOS "i386" "bitcode"

cp /tmp/${CURL_VERSION}-iOS-x86_64-bitcode/include/curl/* iOS/include/curl/

lipo \
	"/tmp/${CURL_VERSION}-iOS-armv7-bitcode/lib/libcurl.a" \
	"/tmp/${CURL_VERSION}-iOS-armv7s-bitcode/lib/libcurl.a" \
	"/tmp/${CURL_VERSION}-iOS-arm64-bitcode/lib/libcurl.a" \
	"/tmp/${CURL_VERSION}-iOS-x86_64-bitcode/lib/libcurl.a" \
	-create -output iOS/lib/libcurl.a
	
#"/tmp/${CURL_VERSION}-iOS-i386-bitcode/lib/libcurl.a" \

echo "Building iOS libraries (nobitcode)"
buildIOS "armv7" "nobitcode"
buildIOS "armv7s" "nobitcode"
buildIOS "arm64" "nobitcode"
buildIOS "x86_64" "nobitcode"
#buildIOS "i386" "nobitcode"

lipo \
	"/tmp/${CURL_VERSION}-iOS-armv7-nobitcode/lib/libcurl.a" \
	"/tmp/${CURL_VERSION}-iOS-armv7s-nobitcode/lib/libcurl.a" \
	"/tmp/${CURL_VERSION}-iOS-arm64-nobitcode/lib/libcurl.a" \
	"/tmp/${CURL_VERSION}-iOS-x86_64-nobitcode/lib/libcurl.a" \
	-create -output iOS/lib/libcurl_nobitcode.a
	
#"/tmp/${CURL_VERSION}-iOS-i386-nobitcode/lib/libcurl.a" \
}

buildTVOSLibsOnly()
{
mkdir -p tvOS/lib
mkdir -p tvOS/include/curl/

echo "Building tvOS libraries (bitcode)"
buildTVOS "arm64"
buildTVOS "x86_64"

cp /tmp/${CURL_VERSION}-tvOS-x86_64/include/curl/* tvOS/include/curl/

lipo \
	"/tmp/${CURL_VERSION}-tvOS-arm64/lib/libcurl.a" \
	"/tmp/${CURL_VERSION}-tvOS-x86_64/lib/libcurl.a" \
	-create -output tvOS/lib/libcurl.a
}


buildMacLibsOnly
buildIOSLibsOnly
buildTVOSLibsOnly

echo "Cleaning up"
rm -rf /tmp/${CURL_VERSION}-*
rm -rf ${CURL_VERSION}
echo "Checking CURL Apple libraries"
xcrun -sdk iphoneos lipo -info Mac/lib/*.a
xcrun -sdk iphoneos lipo -info iOS/lib/*.a
xcrun -sdk iphoneos lipo -info tvOS/lib/*.a

#reset trap
trap - INT TERM EXIT

echo "Done"
