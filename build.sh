#!/bin/bash

# This script builds openssl+libcurl libraries for the Mac, iOS and tvOS 
#
# Jason Cox, @jasonacox
#   https://github.com/jasonacox/Build-OpenSSL-cURL
#

########################################
# EDIT this section to Select Versions #
########################################

OPENSSL="1.0.2o"
OPENSSL_ANDROID=$OPENSSL
LIBCURL="7.58.0"
NGHTTP2="1.24.0"

########################################

# HTTP2 Support?
NOHTTP2="/tmp/no-http2"
rm -f $NOHTTP2

usage ()
{
        #echo "usage: $0 [-disable-http2]"
		echo "---- Build OpenSSL & cURL libraries for Apple/Android platforms ----
-h -> help
-l -> ssl/curl/<> If not specified, builds all
-p -> android/tvos/ios/mac	-> the target platform
-a -> target architure (not yet supported)
-q -> quieter output
example: ./<> -q -l ssl -p apple
__________________________________________________________
		"
        exit 127
}

export RUNNING_ON_OS=''
unamestr=`uname`
if [[ "$unamestr" == 'Linux' ]]; then
   export RUNNING_ON_OS='linux/'
fi

echo "RUNNING_ON_OS : ${RUNNING_ON_OS}"

BUILD_LIBS=""
TARGET_PLATFORM=""
TARGET_ARCH=""
verbose=1
QUIET_DEBUG=""

BUILD_OPENSSL=1
BUILD_CURL=1
BUILD_HTTP2=0
BUILD_FOR_APPLE=1
BUILD_FOR_ANDROID=1

while getopts "h?l:p:a:q" opt; do
    case "$opt" in
    h|\?)
        usage
        ;;
	l)	BUILD_LIBS=$OPTARG
		;;
	p)	TARGET_PLATFORM=$OPTARG
		;;
	a)	TARGET_ARCH=$OPTARG
		;;
    q)  verbose=0
        ;;
    esac
done

if [ "$BUILD_LIBS" == "curl" ]; then
	BUILD_OPENSSL=0
elif [ "$BUILD_LIBS" == "ssl" ]; then
	BUILD_CURL=0
fi

if [ "$TARGET_PLATFORM" == "apple" ]; then
	BUILD_FOR_ANDROID=0
elif [ "$TARGET_PLATFORM" == "android" ]; then
	BUILD_FOR_APPLE=0
fi

echo "_____________________________"
echo "Summary : "
if [ "$BUILD_FOR_APPLE" == 1 ];then
	echo "Build for Apple"
fi
if [ "$BUILD_FOR_ANDROID" == 1 ];then
	echo "Build for Android"
fi
if [ "$BUILD_OPENSSL" == 1 ];then
	echo "Build Openssl"
fi
if [ "$BUILD_CURL" == 1 ];then
	echo "Build cURL"
fi
echo "_____________________________"

if [ "$verbose" == 1 ]; then
	set -o xtrace
else
	QUIET_DEBUG="-q"
fi

if [ "$BUILD_OPENSSL" == 1 ];then	
	echo
	echo "________________"
	echo "Building OpenSSL"
	echo "________________"

	cd openssl 


	if [ "$BUILD_FOR_APPLE" == 1 ];then
		echo "Building for Apple"
		echo "-_-_-_-_-_-_-_-_-_"
		./openssl-build.sh -v "$OPENSSL" $QUIET_DEBUG
	fi

	if [ "$BUILD_FOR_ANDROID" == 1 ];then
		echo "Building for Android"
		echo "-_-_-_-_-_-_-_-_-_-_"
		#./openssl-build-android.sh -v "$OPENSSL_ANDROID" $QUIET_DEBUG
		./openssl-build-android.sh -v "$OPENSSL_ANDROID" $QUIET_DEBUG
	fi

	cd ..
fi

if [ "$BUILD_HTTP2" == 1 ];then	
	echo
	echo "Building nghttp2 for HTTP2 support"
	cd nghttp2
	./nghttp2-build.sh "$NGHTTP2"
	cd ..
else 
	touch "$NOHTTP2"
	NGHTTP2="NONE"	
fi

if [ "$BUILD_CURL" == 1 ];then
	echo
	echo "________________"
	echo "Building Curl"
	echo "________________"

	cd curl

	if [ "$BUILD_FOR_APPLE" == 1 ];then
		echo "Building for Apple"
		echo "-_-_-_-_-_-_-_-_-_"
		./libcurl-build.sh -v "$LIBCURL" $QUIET_DEBUG
	fi

	if [ "$BUILD_FOR_ANDROID" == 1 ];then
		echo "Building for Android"
		echo "-_-_-_-_-_-_-_-_-_-_"
		./libcurl-build-android.sh -v "$LIBCURL" $QUIET_DEBUG
	fi

	cd ..
fi

if [ "$BUILD_FOR_APPLE" == 1 ];then
	echo 
	echo "Libraries..."
	echo
	echo "openssl [$OPENSSL]"
	xcrun -sdk iphoneos lipo -info openssl/*/lib/*.a
	echo
	echo "nghttp2 (rename to libnghttp2.a) [$NGHTTP2]"
	xcrun -sdk iphoneos lipo -info nghttp2/lib/*.a
	echo
	echo "libcurl (rename to libcurl.a) [$LIBCURL]"
	xcrun -sdk iphoneos lipo -info curl/*/lib/*.a
fi

echo
ARCHIVE="archive/libcurl-$LIBCURL-openssl-$OPENSSL-nghttp2-$NGHTTP2"
echo "Creating archive in $ARCHIVE..."
mkdir -p "$ARCHIVE"

if [ "$BUILD_FOR_APPLE" == 1 ];then
	mkdir -p "$ARCHIVE/Apple/curl"
	mkdir -p "$ARCHIVE/Apple/openssl"

	cp -r curl/Mac $ARCHIVE/Apple/curl/
	cp -r openssl/Mac $ARCHIVE/Apple/openssl/
	cp -r curl/iOS $ARCHIVE/Apple/curl/
	cp -r openssl/iOS $ARCHIVE/Apple/openssl/
	cp -r curl/tvOS $ARCHIVE/Apple/curl/
	cp -r openssl/tvOS $ARCHIVE/Apple/openssl/
fi

if [ "$BUILD_FOR_ANDROID" == 1 ];then
	mkdir -p "$ARCHIVE/Android/curl"
	mkdir -p "$ARCHIVE/Android/openssl"
	mkdir -p "$ARCHIVE/Android/common"

	#cp curl/lib/*.a $ARCHIVE
	if [ "$BUILD_CURL" == 1 ];then
		cp -r curl/Android/* $ARCHIVE/Android/curl/
	fi
	if [ "$BUILD_OPENSSL" == 1 ];then
		cp -r openssl/Android/* $ARCHIVE/Android/openssl/
	fi
	cp -r openssl/Android/common/* $ARCHIVE/Android/common/
fi

echo "Archiving Mac binaries for curl and openssl..."
if [ "$BUILD_CURL" == 1 ];then
	mv /tmp/curl $ARCHIVE
	curl https://curl.haxx.se/ca/cacert.pem > $ARCHIVE/cacert.pem
	$ARCHIVE/curl -V
fi


if [ "$BUILD_FOR_ANDROID" == 1 ];then
	mv /tmp/openssl $ARCHIVE
fi

rm -f $NOHTTP2
